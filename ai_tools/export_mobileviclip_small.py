#!/usr/bin/env python3
"""Export and verify MobileViCLIP Small from the upstream PyTorch checkpoint.

The source checkpoint is the official MobileViCLIP training checkpoint, not a
TorchScript file, so this script reconstructs the upstream model code before
exporting the video vision encoder and optionally the text encoder.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import statistics
import sys
import time
import types
from pathlib import Path
from typing import Any

import numpy as np
import onnx
import torch
import torch.nn.functional as F
from torch import nn

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CHECKPOINT = Path(__file__).resolve().parent / "mobileviclip_small.pt"
DEFAULT_VENDOR_DIR = REPO_ROOT / "ai_tools" / "vendor" / "mobileviclip"
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "exported_models" / "mobileviclip_small"


class AttrDict(dict):
    def __getattr__(self, key: str) -> Any:
        return self[key]

    def __setattr__(self, key: str, value: Any) -> None:
        self[key] = value


class MobileViClipVisionEncoder(nn.Module):
    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, video: torch.Tensor) -> torch.Tensor:
        """
        Args:
            video: [B, T, C, H, W] - batch size, frames, channels, height, width
        
        Returns:
            embedding: [B, 512] - normalized embedding
        """
        embedding = self.model.encode_vision(video)
        return F.normalize(embedding, dim=-1)


class MobileViClipTextEncoder(nn.Module):
    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, text_ids: torch.Tensor) -> torch.Tensor:
        """
        Args:
            text_ids: [B, seq_len] - tokenized text input
        
        Returns:
            embedding: [B, 512] - normalized text embedding
        """
        embedding = self.model.encode_text(text_ids)
        return F.normalize(embedding, dim=-1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def install_import_shims(vendor_dir: Path) -> None:
    """Avoid importing unused upstream modules that require FlashAttention."""

    sys.path.insert(0, str(vendor_dir))
    models_dir = vendor_dir / "models"

    models_pkg = types.ModuleType("models")
    models_pkg.__path__ = [str(models_dir)]
    sys.modules["models"] = models_pkg

    backbones_pkg = types.ModuleType("models.backbones")
    backbones_pkg.__path__ = [str(models_dir / "backbones")]
    sys.modules["models.backbones"] = backbones_pkg

    internvideo_pkg = types.ModuleType("models.backbones.internvideo2")
    internvideo_pkg.__path__ = [str(models_dir / "backbones" / "internvideo2")]

    class DummyTextTransformer(nn.Module):
        def __init__(self, *_: Any, **__: Any) -> None:
            super().__init__()

    class DummyClipTokenizer:
        def __init__(self, *_: Any, **__: Any) -> None:
            pass

    class DummyInternVideo2(nn.Module):
        pass

    internvideo_pkg.TextTransformer = DummyTextTransformer
    internvideo_pkg.ClipTokenizer = DummyClipTokenizer
    internvideo_pkg.InternVideo2 = DummyInternVideo2
    sys.modules["models.backbones.internvideo2"] = internvideo_pkg


def load_upstream_module(vendor_dir: Path) -> Any:
    install_import_shims(vendor_dir)
    module_path = vendor_dir / "models" / "mobileviclip_small.py"
    spec = importlib.util.spec_from_file_location(
        "models.mobileviclip_small",
        module_path,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to import {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def build_config(
    mobileclip_ckpt: Path | None = None,
    mobileviclip_ckpt: Path | None = None,
) -> AttrDict:
    """Build configuration for MobileViCLIP Small model.
    
    Args:
        mobileclip_ckpt: Path to MobileCLIP S2 checkpoint. If provided, 
                        auto-loads via load_checkpoint method.
        mobileviclip_ckpt: Path to MobileViCLIP checkpoint for extra weights.
    
    Returns:
        Configuration dict. If checkpoints are None, will disable auto-loading.
    """
    config = AttrDict(
        model=AttrDict(
            text_encoder=AttrDict(name="mobileclip_s2"),
            vision_encoder=AttrDict(
                img_size=256,
                clip_embed_dim=512,
                attn_pool_num_heads=16,
                head_drop_path_rate=0.0,
            ),
            temp=0.01,
            temp_min=0.01,
            freeze_vision=False,
            freeze_text=False,
            open_vision_clip_projector=True,
            open_text_projection=False,
            # Use actual checkpoint paths if provided, otherwise mark as unused
            vision_ckpt_path=str(mobileclip_ckpt) if mobileclip_ckpt else "unused",
            text_ckpt_path=str(mobileclip_ckpt) if mobileclip_ckpt else "unused",
        )
    )
    
    # Add extra checkpoint path if provided
    if mobileviclip_ckpt:
        config.model.extra_ckpt_path = str(mobileviclip_ckpt)
    
    return config


def load_model(
    checkpoint: Path,
    vendor_dir: Path,
    mobileclip_ckpt: Path | None = None,
) -> tuple[nn.Module, nn.Module]:
    """Load MobileViCLIP Small model with proper checkpoint handling.
    
    Args:
        checkpoint: Path to MobileViCLIP Small checkpoint (mobileviclip_small.pt)
        vendor_dir: Path to MobileViCLIP source directory
        mobileclip_ckpt: Optional path to MobileCLIP S2 checkpoint. 
                        If None, will try to load from checkpoint file itself.
    
    Returns:
        tuple of (vision_encoder, text_encoder) - both wrapped for export
    
    Note:
        The MobileViCLIP checkpoint contains both vision and text encoders
        already initialized with MobileCLIP weights. We simply load them.
    """
    if not checkpoint.exists():
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint}")
    if not vendor_dir.exists():
        raise FileNotFoundError(
            f"MobileViCLIP source not found: {vendor_dir}. "
            "Clone https://github.com/MCG-NJU/MobileViCLIP.git there."
        )

    cwd = Path.cwd()
    os.chdir(vendor_dir)
    try:
        module = load_upstream_module(vendor_dir)
        
        # Create config - disable auto-loading if we'll load manually
        config = build_config(mobileclip_ckpt=mobileclip_ckpt)
        
        # If not providing mobileclip checkpoint, disable load_checkpoint
        # since we'll load manually from mobileviclip checkpoint
        if not mobileclip_ckpt:
            module.MobileViCLIP_Small.load_checkpoint = lambda self, *args, **kwargs: None
        
        model = module.MobileViCLIP_Small(config)
    finally:
        os.chdir(cwd)

    # Load checkpoint
    raw = torch.load(checkpoint, map_location="cpu")
    state = raw["module"] if isinstance(raw, dict) and "module" in raw else raw
    
    # Extract both vision and text encoder weights
    model_state = {
        key: value
        for key, value in state.items()
        if key == "temp" 
        or key.startswith("vision_encoder.") 
        or key.startswith("text_encoder.")
    }
    
    message = model.load_state_dict(model_state, strict=False)
    if message.missing_keys or message.unexpected_keys:
        # This is expected since we only load vision and text encoders
        print(f"Note: Loading checkpoint with some keys missing/unexpected:")
        if message.missing_keys:
            print(f"  Missing: {message.missing_keys[:5]}...")
        if message.unexpected_keys:
            print(f"  Unexpected: {message.unexpected_keys[:5]}...")

    # Disable checkpointing during inference for faster export
    for child in model.modules():
        if hasattr(child, "with_cp"):
            child.with_cp = False

    vision_wrapper = MobileViClipVisionEncoder(model)
    vision_wrapper.eval()
    
    text_wrapper = MobileViClipTextEncoder(model)
    text_wrapper.eval()
    
    return vision_wrapper, text_wrapper


def export_onnx(
    model: nn.Module,
    output_path: Path,
    sample: torch.Tensor,
    model_type: str = "vision",
) -> None:
    """Export model to ONNX format.
    
    Args:
        model: The model to export (vision or text encoder)
        output_path: Output ONNX file path
        sample: Sample input tensor for tracing
        model_type: "vision" or "text" - used for naming and validation
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    external_data_path = output_path.with_suffix(output_path.suffix + ".data")
    if external_data_path.exists():
        external_data_path.unlink()
    
    # Use appropriate input/output names based on model type
    if model_type == "vision":
        input_names = ["video"]
        output_names = ["embedding"]
    else:  # text
        input_names = ["text_ids"]
        output_names = ["embedding"]
    
    torch.onnx.export(
        model,
        sample,
        output_path,
        input_names=input_names,
        output_names=output_names,
        opset_version=18,
        do_constant_folding=True,
        dynamo=False,
    )
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)
    onnx.save_model(onnx_model, output_path, save_as_external_data=False)
    if external_data_path.exists():
        external_data_path.unlink()


def export_coreml(
    model: nn.Module,
    output_path: Path,
    sample: torch.Tensor,
    model_type: str = "vision",
) -> dict[str, Any]:
    """Export model to Core ML format (macOS/iOS).
    
    Args:
        model: The model to export (vision or text encoder)
        output_path: Output mlpackage directory
        sample: Sample input tensor for tracing
        model_type: "vision" or "text" - used for input/output naming
    """
    try:
        import coremltools as ct
    except Exception as exc:
        return {"available": False, "reason": "coremltools import failed", "exception": repr(exc)}

    try:
        traced = torch.jit.trace(model, sample, strict=False)
        
        # Set appropriate input/output names based on model type
        if model_type == "vision":
            input_name = "video"
        else:
            input_name = "text_ids"
        output_name = "embedding"
        
        mlmodel = ct.convert(
            traced,
            source="pytorch",
            inputs=[
                ct.TensorType(
                    name=input_name,
                    shape=sample.shape,
                    dtype=np.float32,
                )
            ],
            outputs=[ct.TensorType(name=output_name)],
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS17,
        )
        if output_path.exists():
            import shutil

            shutil.rmtree(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        mlmodel.save(str(output_path))
        return {
            "available": True,
            "asset": output_path.resolve().relative_to(REPO_ROOT).as_posix(),
            "note": "Created on Windows; runtime accuracy/performance must be measured on macOS/iOS Core ML.",
        }
    except Exception as exc:
        return {
            "available": False,
            "reason": "Core ML conversion failed in this environment",
            "exception": repr(exc),
        }


def benchmark_torch(model: nn.Module, sample: torch.Tensor, runs: int) -> dict[str, Any]:
    with torch.no_grad():
        for _ in range(2):
            model(sample)
        times = []
        output = None
        for _ in range(runs):
            start = time.perf_counter()
            output = model(sample)
            times.append((time.perf_counter() - start) * 1000)
    assert output is not None
    return {
        "embedding": output.detach().cpu().numpy(),
        "mean_ms": statistics.fmean(times),
        "min_ms": min(times),
        "max_ms": max(times),
        "runs": runs,
    }


def benchmark_onnx(
    onnx_path: Path,
    sample: torch.Tensor,
    runs: int,
    model_type: str = "vision",
) -> dict[str, Any]:
    """Benchmark ONNX model.
    
    Args:
        onnx_path: Path to ONNX file
        sample: Sample input tensor
        runs: Number of benchmark runs
        model_type: "vision" or "text" - used for input naming
    """
    import onnxruntime as ort

    session = ort.InferenceSession(
        str(onnx_path),
        providers=["CPUExecutionProvider"],
    )
    input_name = session.get_inputs()[0].name
    feed = {input_name: sample.detach().cpu().numpy().astype(np.float32)}
    for _ in range(2):
        session.run(None, feed)
    times = []
    output = None
    for _ in range(runs):
        start = time.perf_counter()
        output = session.run(None, feed)[0]
        times.append((time.perf_counter() - start) * 1000)
    assert output is not None
    return {
        "embedding": output,
        "mean_ms": statistics.fmean(times),
        "min_ms": min(times),
        "max_ms": max(times),
        "runs": runs,
    }


def tflite_status() -> dict[str, Any]:
    try:
        import tensorflow as tf  # type: ignore

        return {"available": True, "tensorflow": tf.__version__}
    except Exception as exc:
        return {
            "available": False,
            "reason": (
                "TensorFlow/ai-edge-torch converter wheels are not available for "
                "Windows CPython 3.14 in this ai_tools/.venv environment."
            ),
            "exception": repr(exc),
        }


def compare(reference: np.ndarray, candidate: np.ndarray) -> dict[str, float]:
    ref = reference.reshape(-1).astype(np.float64)
    cand = candidate.reshape(-1).astype(np.float64)
    diff = ref - cand
    denom = (np.linalg.norm(ref) * np.linalg.norm(cand)) or 1.0
    return {
        "max_abs": float(np.max(np.abs(diff))),
        "mean_abs": float(np.mean(np.abs(diff))),
        "cosine": float(np.dot(ref, cand) / denom),
    }


def write_metadata(
    output_dir: Path,
    checkpoint: Path,
    onnx_path: Path,
    report: dict[str, Any],
    model_type: str = "vision",
) -> None:
    """Write model metadata to JSON file.
    
    Args:
        output_dir: Output directory
        checkpoint: Path to source checkpoint
        onnx_path: Path to exported ONNX model
        report: Benchmark/verification report
        model_type: "vision" or "text" - affects input shape and names
    """
    asset_path = onnx_path.resolve().relative_to(REPO_ROOT).as_posix()
    
    # Configure input/output based on model type
    if model_type == "vision":
        input_spec = {
            "name": "video",
            "shape": [1, 8, 3, 256, 256],
            "dtype": "float32",
            "layout": "B,T,C,H,W",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
        }
        model_description = "MobileViCLIP Small vision encoder"
    else:  # text
        input_spec = {
            "name": "text_ids",
            "shape": [1, 77],  # Standard CLIP tokenization length
            "dtype": "int64",
            "layout": "B,seq_len",
        }
        model_description = "MobileViCLIP Small text encoder"
    
    metadata = {
        "model": model_description,
        "format": "onnx",
        "asset": asset_path,
        "input": input_spec,
        "output": {"name": "embedding", "shape": [1, 512], "normalized": True},
        "checkpoint": {
            "path": str(checkpoint),
            "sha256": sha256_file(checkpoint),
        },
        "source": "https://github.com/MCG-NJU/MobileViCLIP",
        "verification": report,
    }
    
    metadata_file = output_dir / f"mobileviclip_small_{model_type}_metadata.json"
    metadata_file.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export MobileViCLIP Small vision and/or text encoders"
    )
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=DEFAULT_CHECKPOINT,
        help="Path to MobileViCLIP Small checkpoint (.pt file)",
    )
    parser.add_argument(
        "--vendor-dir",
        type=Path,
        default=DEFAULT_VENDOR_DIR,
        help="Path to MobileViCLIP source directory",
    )
    parser.add_argument(
        "--mobileclip-ckpt",
        type=Path,
        default=None,
        help="Optional: Path to MobileCLIP S2 checkpoint. Usually embedded in mobileviclip_small.pt",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Output directory for exported models",
    )
    parser.add_argument(
        "--export-vision",
        action="store_true",
        default=True,
        help="Export vision encoder (default: True)",
    )
    parser.add_argument(
        "--skip-vision",
        action="store_true",
        help="Skip vision encoder export",
    )
    parser.add_argument(
        "--export-text",
        action="store_true",
        help="Export text encoder (default: False, usually same as MobileCLIP)",
    )
    parser.add_argument(
        "--skip-coreml",
        action="store_true",
        help="Skip Core ML conversion",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=5,
        help="Number of benchmark runs",
    )
    args = parser.parse_args()

    # Validate checkpoint exists
    if not args.checkpoint.exists():
        print(f"Error: Checkpoint not found at {args.checkpoint}", file=sys.stderr)
        return 1

    # Determine what to export
    export_vision = not args.skip_vision
    export_text = args.export_text

    if not export_vision and not export_text:
        print("Error: Must export at least vision or text encoder", file=sys.stderr)
        return 1

    torch.manual_seed(20260524)
    np.random.seed(20260524)

    try:
        # Load model with optional MobileCLIP checkpoint
        vision_encoder, text_encoder = load_model(
            args.checkpoint, 
            args.vendor_dir,
            mobileclip_ckpt=args.mobileclip_ckpt,
        )
    except Exception as e:
        print(f"Error loading model: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)
    results = {}

    # Export vision encoder
    if export_vision:
        print("=" * 60)
        print("EXPORTING VISION ENCODER")
        print("=" * 60)
        vision_sample = torch.randn(1, 8, 3, 256, 256, dtype=torch.float32)
        
        try:
            vision_onnx_path = args.output_dir / "mobileviclip_small_vision.onnx"
            export_onnx(vision_encoder, vision_onnx_path, vision_sample, "vision")
            print(f"✓ Exported ONNX: {vision_onnx_path}")
            
            if not args.skip_coreml:
                vision_coreml_path = args.output_dir / "mobileviclip_small_vision.mlpackage"
                vision_coreml_result = export_coreml(
                    vision_encoder, vision_coreml_path, vision_sample, "vision"
                )
            else:
                vision_coreml_result = {"available": False, "reason": "Skipped by --skip-coreml"}
            
            # Benchmark
            vision_torch_result = benchmark_torch(vision_encoder, vision_sample, args.runs)
            vision_onnx_result = benchmark_onnx(
                vision_onnx_path, vision_sample, args.runs, "vision"
            )
            vision_loss = compare(vision_torch_result["embedding"], vision_onnx_result["embedding"])
            
            vision_report = {
                "torch_cpu": {k: v for k, v in vision_torch_result.items() if k != "embedding"},
                "onnx_cpu": {k: v for k, v in vision_onnx_result.items() if k != "embedding"},
                "onnx_vs_torch": vision_loss,
                "coreml": vision_coreml_result,
                "tflite": tflite_status(),
            }
            results["vision"] = vision_report
            
            # Write metadata
            write_metadata(
                args.output_dir, args.checkpoint, vision_onnx_path, vision_report, "vision"
            )
            print(f"✓ Benchmark report written")
            print(json.dumps(vision_report, ensure_ascii=False, indent=2))
            
        except Exception as e:
            print(f"✗ Error exporting vision encoder: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            return 1

    # Export text encoder (optional)
    if export_text:
        print("\n" + "=" * 60)
        print("EXPORTING TEXT ENCODER")
        print("=" * 60)
        print("Note: Text encoder uses tokenized input (shape: [1, 77])")
        text_sample = torch.randint(0, 49408, (1, 77), dtype=torch.int64)
        
        try:
            text_onnx_path = args.output_dir / "mobileviclip_small_text.onnx"
            # Note: For text input, we need to convert to float32 for ONNX export
            # The actual tokenization should be done separately
            export_onnx(text_encoder, text_onnx_path, text_sample.float(), "text")
            print(f"✓ Exported ONNX: {text_onnx_path}")
            
            if not args.skip_coreml:
                text_coreml_path = args.output_dir / "mobileviclip_small_text.mlpackage"
                text_coreml_result = export_coreml(
                    text_encoder, text_coreml_path, text_sample.float(), "text"
                )
            else:
                text_coreml_result = {"available": False, "reason": "Skipped by --skip-coreml"}
            
            # Benchmark
            text_torch_result = benchmark_torch(text_encoder, text_sample.float(), args.runs)
            text_onnx_result = benchmark_onnx(
                text_onnx_path, text_sample.float(), args.runs, "text"
            )
            text_loss = compare(text_torch_result["embedding"], text_onnx_result["embedding"])
            
            text_report = {
                "torch_cpu": {k: v for k, v in text_torch_result.items() if k != "embedding"},
                "onnx_cpu": {k: v for k, v in text_onnx_result.items() if k != "embedding"},
                "onnx_vs_torch": text_loss,
                "coreml": text_coreml_result,
                "note": "Text encoder usually same as MobileCLIP, export for reference",
            }
            results["text"] = text_report
            
            # Write metadata
            write_metadata(
                args.output_dir, args.checkpoint, text_onnx_path, text_report, "text"
            )
            print(f"✓ Benchmark report written")
            print(json.dumps(text_report, ensure_ascii=False, indent=2))
            
        except Exception as e:
            print(f"✗ Error exporting text encoder: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            return 1

    # Summary
    print("\n" + "=" * 60)
    print("EXPORT SUMMARY")
    print("=" * 60)
    print(f"Output directory: {args.output_dir}")
    if "vision" in results:
        print("✓ Vision encoder exported")
    if "text" in results:
        print("✓ Text encoder exported")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
