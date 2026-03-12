import argparse
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps


DEFAULT_ONNX = "mobileclip_vision_ir9.onnx"
DEFAULT_IMAGE = "ai_tools/test_student.png"
DEFAULT_IMAGE_SIZE = 256
DEFAULT_EMBED_DIM = 512
DEFAULT_ENGINEERING_EQUIVALENT = 0.99
DEFAULT_STRICT_EQUIVALENT = 0.999


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Compare 512-d MobileCLIP vectors across the current mobile ONNX "
            "pipeline, the futz12/ncnn_mobileclip preprocessing style, and an "
            "optional dumped NCNN vector."
        )
    )
    parser.add_argument("image", nargs="?", default=DEFAULT_IMAGE)
    parser.add_argument("--onnx", default=DEFAULT_ONNX)
    parser.add_argument("--image-size", type=int, default=DEFAULT_IMAGE_SIZE)
    parser.add_argument(
        "--expected-dim",
        type=int,
        default=DEFAULT_EMBED_DIM,
        help="Expected embedding dimension for ONNX/NCNN vectors.",
    )
    parser.add_argument(
        "--engineering-equivalent-threshold",
        type=float,
        default=DEFAULT_ENGINEERING_EQUIVALENT,
        help="Cosine similarity threshold above which two vectors are treated as engineering-equivalent.",
    )
    parser.add_argument(
        "--strict-equivalent-threshold",
        type=float,
        default=DEFAULT_STRICT_EQUIVALENT,
        help="Cosine similarity threshold above which two vectors are treated as nearly identical.",
    )
    parser.add_argument(
        "--ncnn-vector",
        help="Optional JSON/TXT/NPY/BIN file containing a dumped 512-d NCNN vector.",
    )
    parser.add_argument(
        "--dump-json",
        help="Optional output JSON path for the generated vectors and metrics.",
    )
    return parser.parse_args()


def l2_normalize(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if norm == 0 or np.isnan(norm):
        return vector.astype(np.float32, copy=False)
    return (vector / norm).astype(np.float32, copy=False)


def preprocess_mobile_onnx(image: Image.Image, image_size: int) -> np.ndarray:
    baked = ImageOps.exif_transpose(image).convert("RGB")
    width, height = baked.size
    scale = image_size / min(width, height)
    resized = baked.resize(
        (round(width * scale), round(height * scale)),
        Image.Resampling.BILINEAR,
    )
    left = max(0, (resized.width - image_size) // 2)
    top = max(0, (resized.height - image_size) // 2)
    cropped = resized.crop((left, top, left + image_size, top + image_size))
    return to_nchw_unit_rgb(cropped)


def preprocess_futz12_ncnn_style(image: Image.Image, image_size: int) -> np.ndarray:
    baked = ImageOps.exif_transpose(image).convert("RGB")
    resized = baked.resize((image_size, image_size), Image.Resampling.BILINEAR)
    return to_nchw_unit_rgb(resized)


def to_nchw_unit_rgb(image: Image.Image) -> np.ndarray:
    array = np.asarray(image, dtype=np.float32) / 255.0
    array = np.transpose(array, (2, 0, 1))
    return np.expand_dims(array, axis=0).astype(np.float32, copy=False)


def infer_onnx_image_size(onnx_path: str, fallback: int) -> int:
    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_shape = session.get_inputs()[0].shape
    if len(input_shape) < 4 or not isinstance(input_shape[2], int):
        return fallback
    return int(input_shape[2])


def run_onnx_input(session: ort.InferenceSession, input_tensor: np.ndarray) -> np.ndarray:
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name
    output = session.run([output_name], {input_name: input_tensor})[0]
    vector = np.asarray(output, dtype=np.float32).reshape(-1)
    return l2_normalize(vector)


def validate_vector_dim(name: str, vector: np.ndarray, expected_dim: int) -> np.ndarray:
    if vector.ndim != 1:
        raise ValueError(f"{name} must be 1-D, got shape {vector.shape}")
    if len(vector) != expected_dim:
        raise ValueError(
            f"{name} dim mismatch: expected {expected_dim}, got {len(vector)}"
        )
    return vector.astype(np.float32, copy=False)


def load_ncnn_vector(path: str) -> np.ndarray:
    vector_path = Path(path)
    suffix = vector_path.suffix.lower()

    if suffix == ".npy":
        vector = np.load(vector_path).astype(np.float32).reshape(-1)
        return l2_normalize(vector)

    if suffix == ".bin":
        vector = np.fromfile(vector_path, dtype=np.float32).reshape(-1)
        return l2_normalize(vector)

    text = vector_path.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError(f"Empty NCNN vector file: {path}")

    if suffix == ".json":
        payload = json.loads(text)
        if isinstance(payload, dict):
            if "vector" in payload:
                payload = payload["vector"]
            elif "embedding" in payload:
                payload = payload["embedding"]
        vector = np.asarray(payload, dtype=np.float32).reshape(-1)
        return l2_normalize(vector)

    pieces = [piece for piece in text.replace(",", " ").split() if piece]
    vector = np.asarray([float(piece) for piece in pieces], dtype=np.float32).reshape(-1)
    return l2_normalize(vector)


def compare_vectors(name: str, left: np.ndarray, right: np.ndarray) -> dict:
    usable = min(len(left), len(right))
    left = left[:usable]
    right = right[:usable]

    cosine = float(np.dot(left, right))
    abs_diff = np.abs(left - right)
    return {
        "name": name,
        "dims": usable,
        "cosine": cosine,
        "max_abs_diff": float(np.max(abs_diff)),
        "mean_abs_diff": float(np.mean(abs_diff)),
        "first8_left": [float(value) for value in left[:8]],
        "first8_right": [float(value) for value in right[:8]],
    }


def classify_cosine_similarity(
    cosine: float,
    engineering_equivalent_threshold: float,
    strict_equivalent_threshold: float,
) -> str:
    if cosine >= strict_equivalent_threshold:
        return "nearly_identical"
    if cosine >= engineering_equivalent_threshold:
        return "engineering_equivalent"
    return "materially_different"


def print_vector_preview(name: str, vector: np.ndarray):
    preview = ", ".join(f"{value:.6f}" for value in vector[:8])
    print(f"{name} first8: [{preview}]")


def print_metrics(
    metrics: dict,
    engineering_equivalent_threshold: float,
    strict_equivalent_threshold: float,
):
    verdict = classify_cosine_similarity(
        metrics["cosine"],
        engineering_equivalent_threshold,
        strict_equivalent_threshold,
    )
    print(f"\n=== {metrics['name']} ===")
    print(f"dims: {metrics['dims']}")
    print(f"cosine: {metrics['cosine']:.8f}")
    print(
        "verdict: "
        f"{verdict} "
        f"(strict>={strict_equivalent_threshold:.3f}, engineering>={engineering_equivalent_threshold:.3f})"
    )
    print(f"max_abs_diff: {metrics['max_abs_diff']:.8f}")
    print(f"mean_abs_diff: {metrics['mean_abs_diff']:.8f}")
    print(
        "left first8: [" + ", ".join(f"{value:.6f}" for value in metrics["first8_left"]) + "]"
    )
    print(
        "right first8: [" + ", ".join(f"{value:.6f}" for value in metrics["first8_right"]) + "]"
    )


def main():
    args = parse_args()
    image_path = Path(args.image)
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    image_size = infer_onnx_image_size(args.onnx, args.image_size)
    session = ort.InferenceSession(args.onnx, providers=["CPUExecutionProvider"])
    image = Image.open(image_path)

    mobile_input = preprocess_mobile_onnx(image, image_size)
    ncnn_style_input = preprocess_futz12_ncnn_style(image, image_size)

    mobile_onnx_vector = validate_vector_dim(
        "mobile_onnx_vector",
        run_onnx_input(session, mobile_input),
        args.expected_dim,
    )
    ncnn_style_onnx_vector = validate_vector_dim(
        "ncnn_style_onnx_vector",
        run_onnx_input(session, ncnn_style_input),
        args.expected_dim,
    )

    print(f"image: {image_path}")
    print(f"onnx: {args.onnx}")
    print(f"image_size: {image_size}")
    print("note: futz12/ncnn_mobileclip image path uses direct resize to square + /255, no center crop")
    print(
        "cosine policy: "
        f">={args.strict_equivalent_threshold:.3f} => nearly_identical, "
        f">={args.engineering_equivalent_threshold:.3f} => engineering_equivalent"
    )
    print_vector_preview("mobile_onnx", mobile_onnx_vector)
    print_vector_preview("ncnn_style_onnx", ncnn_style_onnx_vector)

    results = {
        "image": str(image_path),
        "onnx": args.onnx,
        "image_size": image_size,
        "comparisons": [],
    }

    mobile_vs_ncnn_style = compare_vectors(
        "mobile_onnx vs ncnn_style_onnx",
        mobile_onnx_vector,
        ncnn_style_onnx_vector,
    )
    results["comparisons"].append(mobile_vs_ncnn_style)
    print_metrics(
        mobile_vs_ncnn_style,
        args.engineering_equivalent_threshold,
        args.strict_equivalent_threshold,
    )

    if args.ncnn_vector:
        dumped_ncnn_vector = validate_vector_dim(
            "dumped_ncnn_vector",
            load_ncnn_vector(args.ncnn_vector),
            args.expected_dim,
        )
        print_vector_preview("dumped_ncnn", dumped_ncnn_vector)

        metrics_1 = compare_vectors(
            "mobile_onnx vs dumped_ncnn",
            mobile_onnx_vector,
            dumped_ncnn_vector,
        )
        metrics_2 = compare_vectors(
            "ncnn_style_onnx vs dumped_ncnn",
            ncnn_style_onnx_vector,
            dumped_ncnn_vector,
        )
        results["comparisons"].extend([metrics_1, metrics_2])
        print_metrics(
            metrics_1,
            args.engineering_equivalent_threshold,
            args.strict_equivalent_threshold,
        )
        print_metrics(
            metrics_2,
            args.engineering_equivalent_threshold,
            args.strict_equivalent_threshold,
        )

    if args.dump_json:
        payload = {
            **results,
            "mobile_onnx_vector": [float(value) for value in mobile_onnx_vector.tolist()],
            "ncnn_style_onnx_vector": [float(value) for value in ncnn_style_onnx_vector.tolist()],
        }
        Path(args.dump_json).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"\nSaved comparison JSON to: {args.dump_json}")


if __name__ == "__main__":
    main()