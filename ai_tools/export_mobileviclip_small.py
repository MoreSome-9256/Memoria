#!/usr/bin/env python3
"""Export and verify MobileViCLIP Small from the upstream PyTorch checkpoint.

The source checkpoint is the official MobileViCLIP training checkpoint, not a
TorchScript file, so this script reconstructs the upstream model code before
exporting the video vision encoder.
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
from torch import nn

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CHECKPOINT = Path.home() / "Downloads" / "mobileviclip_small.pt"
DEFAULT_VENDOR_DIR = REPO_ROOT / "ai_tools" / "vendor" / "mobileviclip"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "assets" / "mobileviclip" / "small"


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
        embedding = self.model.encode_vision(video)
        return torch.nn.functional.normalize(embedding, dim=-1)


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


def build_config() -> AttrDict:
    return AttrDict(
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
            vision_ckpt_path="unused",
            text_ckpt_path="unused",
        )
    )


def load_model(checkpoint: Path, vendor_dir: Path) -> MobileViClipVisionEncoder:
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
        module.MobileViCLIP_Small.load_checkpoint = lambda self, *args, **kwargs: None
        model = module.MobileViCLIP_Small(build_config())
    finally:
        os.chdir(cwd)

    raw = torch.load(checkpoint, map_location="cpu")
    state = raw["module"] if isinstance(raw, dict) and "module" in raw else raw
    vision_state = {
        key: value
        for key, value in state.items()
        if key == "temp" or key.startswith("vision_encoder.")
    }
    message = model.load_state_dict(vision_state, strict=False)
    if message.missing_keys or message.unexpected_keys:
        raise RuntimeError(
            "Checkpoint did not match MobileViCLIP Small vision encoder: "
            f"missing={message.missing_keys[:8]} unexpected={message.unexpected_keys[:8]}"
        )

    for child in model.modules():
        if hasattr(child, "with_cp"):
            child.with_cp = False

    wrapper = MobileViClipVisionEncoder(model)
    wrapper.eval()
    return wrapper


def export_onnx(model: nn.Module, output_path: Path, sample: torch.Tensor) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    external_data_path = output_path.with_suffix(output_path.suffix + ".data")
    if external_data_path.exists():
        external_data_path.unlink()
    torch.onnx.export(
        model,
        sample,
        output_path,
        input_names=["video"],
        output_names=["embedding"],
        opset_version=18,
        do_constant_folding=True,
        dynamo=False,
    )
    onnx_model = onnx.load(output_path)
    onnx.checker.check_model(onnx_model)
    onnx.save_model(onnx_model, output_path, save_as_external_data=False)
    if external_data_path.exists():
        external_data_path.unlink()


def export_coreml(model: nn.Module, output_path: Path, sample: torch.Tensor) -> dict[str, Any]:
    try:
        import coremltools as ct
    except Exception as exc:
        return {"available": False, "reason": "coremltools import failed", "exception": repr(exc)}

    try:
        traced = torch.jit.trace(model, sample, strict=False)
        mlmodel = ct.convert(
            traced,
            source="pytorch",
            inputs=[
                ct.TensorType(
                    name="video",
                    shape=sample.shape,
                    dtype=np.float32,
                )
            ],
            outputs=[ct.TensorType(name="embedding")],
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


def benchmark_onnx(onnx_path: Path, sample: torch.Tensor, runs: int) -> dict[str, Any]:
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
) -> None:
    asset_path = onnx_path.resolve().relative_to(REPO_ROOT).as_posix()
    metadata = {
        "model": "MobileViCLIP Small vision encoder",
        "format": "onnx",
        "asset": asset_path,
        "input": {
            "name": "video",
            "shape": [1, 8, 3, 256, 256],
            "dtype": "float32",
            "layout": "B,T,C,H,W",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
        },
        "output": {"name": "embedding", "shape": [1, 512], "normalized": True},
        "checkpoint": {
            "path": str(checkpoint),
            "sha256": sha256_file(checkpoint),
        },
        "source": "https://github.com/MCG-NJU/MobileViCLIP",
        "verification": report,
    }
    (output_dir / "mobileviclip_small_metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument("--vendor-dir", type=Path, default=DEFAULT_VENDOR_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--skip-coreml", action="store_true")
    args = parser.parse_args()

    torch.manual_seed(20260524)
    np.random.seed(20260524)

    model = load_model(args.checkpoint, args.vendor_dir)
    sample = torch.randn(1, 8, 3, 256, 256, dtype=torch.float32)

    onnx_path = args.output_dir / "mobileviclip_small.onnx"
    export_onnx(model, onnx_path, sample)
    coreml_path = args.output_dir / "mobileviclip_small.mlpackage"
    coreml_result = (
        {"available": False, "reason": "Skipped by --skip-coreml"}
        if args.skip_coreml
        else export_coreml(model, coreml_path, sample)
    )

    torch_result = benchmark_torch(model, sample, args.runs)
    onnx_result = benchmark_onnx(onnx_path, sample, args.runs)
    loss = compare(torch_result["embedding"], onnx_result["embedding"])
    report = {
        "torch_cpu": {k: v for k, v in torch_result.items() if k != "embedding"},
        "onnx_cpu": {k: v for k, v in onnx_result.items() if k != "embedding"},
        "onnx_vs_torch": loss,
        "coreml": coreml_result,
        "tflite": tflite_status(),
    }

    args.output_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.output_dir / "mobileviclip_small_benchmark.json"
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    write_metadata(args.output_dir, args.checkpoint, onnx_path, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
