#!/usr/bin/env python3
"""
Export MobileCLIP2-B to ONNX for use with transformers.js.

Generates:
  - vision_model.onnx / text_model.onnx (fp32)
  - vision_model_fp16.onnx (fp16 weights with fp32 I/O for transformers.js)
  - vision_model_quantized.onnx / text_model_quantized.onnx (int8 dynamic quantization)
"""
import argparse
import math
from pathlib import Path
import sys

import torch
import torch.nn.functional as F
import onnx
from huggingface_hub import hf_hub_download, list_repo_files


# =========================================================================
# Monkey patch: replace PyTorch SDPA with explicit matmul/softmax path
# so ONNX export can target lower opset variants.
# =========================================================================
def _math_sdpa(query, key, value, attn_mask=None, dropout_p=0.0, is_causal=False, scale=None):
    scale_factor = scale if scale is not None else (1.0 / math.sqrt(query.size(-1)))
    attn_weight = torch.matmul(query, key.transpose(-2, -1)) * scale_factor

    if is_causal:
        l_size, s_size = query.size(-2), key.size(-2)
        causal_mask = torch.ones(
            l_size,
            s_size,
            dtype=torch.bool,
            device=query.device,
        ).tril()
        attn_weight = attn_weight.masked_fill(~causal_mask, float("-inf"))

    if attn_mask is not None:
        if attn_mask.dtype == torch.bool:
            attn_weight = attn_weight.masked_fill(~attn_mask, float("-inf"))
        else:
            attn_weight = attn_weight + attn_mask

    attn_weight = torch.softmax(attn_weight, dim=-1)
    if dropout_p > 0.0:
        attn_weight = F.dropout(attn_weight, p=dropout_p)

    return torch.matmul(attn_weight, value)


# Force override of PyTorch high-level SDPA implementation.
F.scaled_dot_product_attention = _math_sdpa
# =========================================================================

# =========================================================================
# Monkey patch: replace PyTorch unflatten with reshape
# to support ONNX opset 12 (unflatten was added in 13).
# =========================================================================
def _patched_unflatten(self, dim, sizes):
    shape = list(self.size())
    if dim < 0:
        dim += len(shape)
    # Split target dim into provided sizes; keep others unchanged.
    new_shape = shape[:dim] + list(sizes) + shape[dim + 1 :]
    return self.reshape(new_shape)


# Force override Tensor.unflatten and torch.unflatten helper.
torch.Tensor.unflatten = _patched_unflatten
if hasattr(torch, "unflatten"):
    torch.unflatten = lambda input, dim, sizes: _patched_unflatten(input, dim, sizes)
# =========================================================================


def _pick_weights_file(repo_id: str) -> str:
    files = list_repo_files(repo_id)
    pt_files = [f for f in files if f.endswith(".pt")]
    if not pt_files:
        raise RuntimeError(f"No .pt files found in {repo_id}. Files: {files}")

    def score(name: str) -> int:
        n = name.lower()
        s = 0
        if "mobileclip2" in n:
            s += 2
        if "_b" in n or n.endswith("b.pt"):
            s += 2
        return s

    pt_files.sort(key=score, reverse=True)
    return pt_files[0]


def export_encoder(
    encoder: torch.nn.Module,
    dummy_input: torch.Tensor,
    output_path: Path,
    input_name: str,
    output_name: str,
    opset: int,
) -> None:
    """Export a single encoder to ONNX in fp32."""
    torch.onnx.export(
        encoder,
        dummy_input,
        str(output_path),
        input_names=[input_name],
        output_names=[output_name],
        export_params=True,
        opset_version=opset,
        dynamic_axes={input_name: {0: "batch"}, output_name: {0: "batch"}},
        dynamo=False,
    )
    print(f"Saved: {output_path}")


def convert_to_fp16(model_path: Path) -> Path:
    """
    Convert ONNX model to fp16 weights while keeping I/O as fp32.

    This is the proper approach for transformers.js compatibility:
    - Inputs/outputs remain fp32 (processor compatibility)
    - Internal weights are fp16 (memory savings)
    - Problematic ops are excluded from conversion
    """
    try:
        from onnxconverter_common import float16
    except ImportError:
        print("Warning: onnxconverter-common not available, skipping fp16 conversion")
        print("Install with: pip install onnxconverter-common")
        return None

    # Extended block list to prevent problematic conversions
    # Based on transformers.js float16.py defaults
    op_block_list = [
        'Cast',           # Cast operations should stay as-is
        'CastLike',
        'Range',          # Range needs int/fp32
        'TopK',           # TopK indices need int
        'NonMaxSuppression',
        'NonZero',
        'Unique',
        'Where',          # Conditional ops
        'If',
        'Loop',
        'ReduceSum',      # Reduction ops can lose precision
        'ReduceMean',
        'ReduceMax',
        'ReduceMin',
        'ReduceProd',
        'Softmax',        # Softmax needs numerical stability
        'LogSoftmax',
        'Exp',            # Exp can overflow in fp16
        'Log',
        'Pow',
        'Sqrt',
        'Erf',
    ]

    out_path = model_path.with_name(model_path.stem + "_fp16.onnx")

    try:
        model = onnx.load(str(model_path))
        model_fp16 = float16.convert_float_to_float16(
            model,
            min_positive_val=1e-7,
            max_finite_val=65504.0,  # Max fp16 value
            keep_io_types=True,      # Keep inputs/outputs as fp32
            disable_shape_infer=True,
            op_block_list=op_block_list,
        )
        onnx.save(model_fp16, str(out_path))
        print(f"Saved: {out_path}")
        return out_path
    except Exception as e:
        print(f"Warning: fp16 conversion failed: {e}")
        return None


def quantize_dynamic_int8(model_path: Path) -> None:
    """Quantize ONNX model using dynamic int8 quantization."""
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType
    except ImportError:
        print("Warning: onnxruntime.quantization not available, skipping int8 quantization")
        return

    out_path = model_path.with_name(model_path.stem.replace("_fp16", "") + "_quantized.onnx")
    try:
        quantize_dynamic(
            str(model_path),
            str(out_path),
            weight_type=QuantType.QInt8,
        )
        print(f"Saved: {out_path}")
    except Exception as e:
        print(f"Warning: int8 quantization failed for {model_path.name}: {e}")


def resolve_image_size(model_name: str, image_size_override: int) -> int:
    if image_size_override > 0:
        return image_size_override

    normalized = model_name.upper()
    # MobileCLIP2 S-series defaults to 256. B/L-14 defaults to 224.
    if normalized.endswith("S0") or normalized.endswith("S2") or normalized.endswith("S3") or normalized.endswith("S4"):
        return 256
    return 224


def main() -> None:
    parser = argparse.ArgumentParser(description="Export MobileCLIP2 image/text encoders to ONNX.")
    parser.add_argument("--repo-id", default="apple/MobileCLIP2-B", help="Hugging Face repo id")
    parser.add_argument("--model-name", default="MobileCLIP2-B", help="OpenCLIP model name")
    parser.add_argument("--cache-dir", default="checkpoints", help="Directory to store downloaded weights")
    parser.add_argument("--out-dir", default="onnx", help="Output directory for ONNX files")
    parser.add_argument("--opset", type=int, default=18, help="ONNX opset version")
    parser.add_argument(
        "--image-size",
        type=int,
        default=0,
        help="Vision input image size override. 0 means auto by model name (S*:256, B/L-14:224).",
    )
    parser.add_argument("--skip-fp16", action="store_true", help="Skip fp16 export")
    parser.add_argument("--skip-quantized", action="store_true", help="Skip int8 quantized export")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    cache_dir = (root / args.cache_dir).resolve()
    out_dir = (root / args.out_dir).resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Ensure patched open_clip and vendor mobileclip are importable.
    open_clip_src = root / "open_clip" / "src"
    vendor_dir = root / "vendor"
    if not (open_clip_src / "open_clip").is_dir():
        raise RuntimeError("open_clip not found. Run ./setup_open_clip.sh first.")

    sys.path.insert(0, str(open_clip_src))
    sys.path.insert(0, str(vendor_dir))

    import open_clip  # noqa: E402
    from mobileclip.modules.common.mobileone import reparameterize_model  # noqa: E402

    weights_file = _pick_weights_file(args.repo_id)
    weights_path = hf_hub_download(
        repo_id=args.repo_id,
        filename=weights_file,
        local_dir=cache_dir,
        local_dir_use_symlinks=False,
    )

    model_kwargs = {}
    if not (args.model_name.endswith("S3") or args.model_name.endswith("S4") or args.model_name.endswith("L-14")):
        model_kwargs = {"image_mean": (0, 0, 0), "image_std": (1, 1, 1)}

    model, _, _ = open_clip.create_model_and_transforms(
        args.model_name, pretrained=weights_path, **model_kwargs
    )
    tokenizer = open_clip.get_tokenizer(args.model_name)

    model.eval()
    model = reparameterize_model(model)

    # Dummy inputs for export
    image_size = resolve_image_size(args.model_name, args.image_size)
    image = torch.zeros(1, 3, image_size, image_size, dtype=torch.float32)
    text = tokenizer(["a diagram"])  # shape [1, 77]
    print(f"Using dummy vision input size: {image_size}x{image_size}")

    image_encoder = getattr(model, "visual", None) or getattr(model, "image_encoder")
    text_encoder = getattr(model, "text", None) or getattr(model, "text_encoder")

    # --- Export fp32 versions (primary) ---
    print("\n=== Exporting fp32 models ===")
    vision_fp32 = out_dir / "vision_model.onnx"
    text_fp32 = out_dir / "text_model.onnx"

    export_encoder(image_encoder, image, vision_fp32, "pixel_values", "image_embeds", args.opset)
    export_encoder(text_encoder, text, text_fp32, "input_ids", "text_embeds", args.opset)

    # --- Convert to fp16 (post-conversion with fp32 I/O) ---
    if not args.skip_fp16:
        print("\n=== Converting to fp16 (fp32 I/O + fp16 weights) ===")
        convert_to_fp16(vision_fp32)
        # Note: Text model could also be converted, but it's smaller and less critical

    # --- Export int8 quantized versions ---
    if not args.skip_quantized:
        print("\n=== Exporting int8 quantized models ===")
        quantize_dynamic_int8(vision_fp32)
        quantize_dynamic_int8(text_fp32)

    print("\n=== Done ===")
    print(f"Output directory: {out_dir}")


if __name__ == "__main__":
    main()
