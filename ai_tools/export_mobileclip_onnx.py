#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import sys
import types
from pathlib import Path
from typing import Any

import numpy as np
import onnx
import torch
import torch.nn.functional as F
from torch import nn


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VENDOR_DIR = REPO_ROOT / "ai_tools" / "vendor" / "mobileviclip"
DEFAULT_CKPT_DIR = REPO_ROOT / "ai_tools" / "checkpoints"
DEFAULT_OUTPUT = REPO_ROOT / "assets" / "mobileviclip" / "mobileviclip_video_encoder.onnx"


class AttrDict(dict):
    def __getattr__(self, key: str) -> Any:
        return self[key]

    def __setattr__(self, key: str, value: Any) -> None:
        self[key] = value


def adict(x: Any) -> Any:
    if isinstance(x, dict):
        return AttrDict({k: adict(v) for k, v in x.items()})
    return x


MODEL_SPECS = {
    "tiny": {
        "module": "mobileviclip_tiny",
        "class": "MobileViCLIP_Tiny",
        "mobileclip_name": "mobileclip_s0",
        "mobileclip_ckpt": "mobileclip_s0.pt",
        "mobileviclip_ckpt": "mobileviclip_tiny.pt",
        "open_vision_clip_projector": False,
    },
    "small": {
        "module": "mobileviclip_small",
        "class": "MobileViCLIP_Small",
        "mobileclip_name": "mobileclip_s2",
        "mobileclip_ckpt": "mobileclip_s2.pt",
        "mobileviclip_ckpt": "mobileviclip_small.pt",
        "open_vision_clip_projector": True,
    },
}


class VideoEncoderONNX(nn.Module):
    """
    NCNN-friendly input:
      frames: [8, 3, 256, 256]
    Output:
      normalized embedding: [1, 512]
    """

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, frames: torch.Tensor) -> torch.Tensor:
        video = frames.unsqueeze(0)  # [1, 8, 3, 256, 256]
        emb = self.model.encode_vision(video)
        return F.normalize(emb, dim=-1)


def install_import_shims(vendor_dir: Path) -> None:
    """
    Let models.mobileviclip_*.py import without requiring the unused
    FlashAttention/text InternVideo modules. Vision subpackages still load
    from the real vendor directory via __path__.
    """
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


def load_mobileviclip_module(vendor_dir: Path, module_name: str) -> Any:
    install_import_shims(vendor_dir)

    module_path = vendor_dir / "models" / f"{module_name}.py"
    spec = importlib.util.spec_from_file_location(f"models.{module_name}", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import {module_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def build_config(spec: dict[str, Any], mobileclip_ckpt: Path, mobileviclip_ckpt: Path) -> AttrDict:
    return adict(
        {
            "model": {
                "vision_encoder": {
                    "name": spec["mobileclip_name"],
                    "img_size": 256,
                    "head_drop_path_rate": 0.0,
                    "attn_pool_num_heads": 16,
                    "clip_embed_dim": 512,
                    "align_dim": 512,
                },
                "text_encoder": {
                    "name": spec["mobileclip_name"],
                },
                "temp": 1 / 100.0,
                "temp_min": 1 / 100.0,
                "freeze_vision": False,
                "freeze_text": True,
                "open_vision_clip_projector": spec["open_vision_clip_projector"],
                "open_text_projection": False,
                "vision_ckpt_path": str(mobileclip_ckpt),
                "text_ckpt_path": str(mobileclip_ckpt),
                "extra_ckpt_path": str(mobileviclip_ckpt),
                "load_vision_ckpt_from_internvideo2_stage2": False,
            }
        }
    )


def load_base_vision_state(mobileclip_ckpt: Path) -> dict[str, torch.Tensor]:
    """
    Equivalent to upstream vision checkpoint mapping:
      Apple MobileCLIP image_encoder.model.* -> MobileViCLIP vision_encoder.*
    """
    raw = torch.load(mobileclip_ckpt, map_location="cpu")
    if isinstance(raw, dict) and "module" in raw:
        raw = raw["module"]

    image_state = {}
    for k, v in raw.items():
        if "image_encoder.model." in k:
            k = k.replace("image_encoder.model.", "")
            image_state[k] = v
        else:
            image_state[k] = v

    vision_state = {}
    for k, v in image_state.items():
        if k.startswith(("clip_decoder.", "mae_decoder.", "final_clip_decoder.")):
            continue
        if k in ("clip_pos_embed", "mae_pos_embed"):
            continue
        vision_state[f"vision_encoder.{k}"] = v

    return vision_state


def load_extra_state(mobileviclip_ckpt: Path) -> dict[str, torch.Tensor]:
    raw = torch.load(mobileviclip_ckpt, map_location="cpu")
    if isinstance(raw, dict) and "module" in raw:
        raw = raw["module"]
    return {
        k: v
        for k, v in raw.items()
        if k == "temp" or k.startswith("vision_encoder.")
    }


def reparameterize_vision(model: nn.Module) -> None:
    from models.backbones.internvideo2.mobileclip.modules.common.mobileone import (
        reparameterize_model,
    )

    model.vision_encoder = reparameterize_model(model.vision_encoder).eval()

    for m in model.modules():
        if hasattr(m, "with_cp"):
            m.with_cp = False


def build_model(model_size: str, vendor_dir: Path, ckpt_dir: Path) -> nn.Module:
    spec = MODEL_SPECS[model_size]
    mobileclip_ckpt = ckpt_dir / spec["mobileclip_ckpt"]
    mobileviclip_ckpt = ckpt_dir / spec["mobileviclip_ckpt"]

    if not vendor_dir.exists():
        raise FileNotFoundError(f"MobileViCLIP source not found: {vendor_dir}")
    if not mobileclip_ckpt.exists():
        raise FileNotFoundError(f"MobileCLIP base checkpoint not found: {mobileclip_ckpt}")
    if not mobileviclip_ckpt.exists():
        raise FileNotFoundError(f"MobileViCLIP checkpoint not found: {mobileviclip_ckpt}")

    module = load_mobileviclip_module(vendor_dir, spec["module"])
    cls = getattr(module, spec["class"])

    # We export vision only. Avoid constructing/loading the real text tower.
    cls.build_text_encoder = lambda self, cfg, projection_dim: nn.Identity()
    cls.load_checkpoint = lambda self, *args, **kwargs: None

    cwd = Path.cwd()
    os.chdir(vendor_dir)
    try:
        cfg = build_config(spec, mobileclip_ckpt, mobileviclip_ckpt)
        model = cls(cfg, tokenizer=None, is_pretrain=False)
    finally:
        os.chdir(cwd)

    state = {}
    state.update(load_base_vision_state(mobileclip_ckpt))
    state.update(load_extra_state(mobileviclip_ckpt))

    msg = model.load_state_dict(state, strict=False)

    bad_missing = [
        k for k in msg.missing_keys
        if k.startswith("vision_encoder.") or k == "temp"
    ]
    if bad_missing or msg.unexpected_keys:
        raise RuntimeError(
            "Bad checkpoint load:\n"
            f"missing={bad_missing[:20]}\n"
            f"unexpected={msg.unexpected_keys[:20]}"
        )

    model.eval()
    model.requires_grad_(False)
    reparameterize_vision(model)

    return VideoEncoderONNX(model).eval()


def export_onnx(model: nn.Module, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)

    sample = torch.randn(8, 3, 256, 256, dtype=torch.float32)

    with torch.no_grad():
        torch.onnx.export(
            model,
            sample,
            output,
            input_names=["frames"],
            output_names=["embedding"],
            opset_version=17,
            do_constant_folding=True,
            dynamic_axes=None,
        )

    onnx_model = onnx.load(output)
    onnx.checker.check_model(onnx_model)
    onnx.save(onnx_model, output)


def verify_onnx(model: nn.Module, output: Path) -> None:
    import onnxruntime as ort

    sample = torch.randn(8, 3, 256, 256, dtype=torch.float32)

    with torch.no_grad():
        torch_out = model(sample).cpu().numpy()

    session = ort.InferenceSession(str(output), providers=["CPUExecutionProvider"])
    onnx_out = session.run(None, {"frames": sample.numpy()})[0]

    diff = np.abs(torch_out - onnx_out)
    cosine = float(
        np.dot(torch_out.reshape(-1), onnx_out.reshape(-1))
        / (np.linalg.norm(torch_out) * np.linalg.norm(onnx_out) + 1e-12)
    )

    print(f"ONNX saved: {output}")
    print(f"max_abs={diff.max():.8f}")
    print(f"mean_abs={diff.mean():.8f}")
    print(f"cosine={cosine:.8f}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=["tiny", "small"], default="small")
    parser.add_argument("--vendor-dir", type=Path, default=DEFAULT_VENDOR_DIR)
    parser.add_argument("--ckpt-dir", type=Path, default=DEFAULT_CKPT_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--no-verify", action="store_true")
    args = parser.parse_args()

    torch.manual_seed(20260528)

    model = build_model(args.model, args.vendor_dir, args.ckpt_dir)
    export_onnx(model, args.output)

    if not args.no_verify:
        verify_onnx(model, args.output)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())