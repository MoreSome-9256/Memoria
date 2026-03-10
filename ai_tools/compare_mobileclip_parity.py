import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import mobileclip
import numpy as np
import onnxruntime as ort
import torch
from PIL import Image, ImageOps


MODEL_NAME = "mobileclip_s2"
CHECKPOINT = "checkpoints/mobileclip_s2.pt"
DEFAULT_ONNX = "mobileclip_vision_ir9.onnx"
DEFAULT_IMAGE = "ai_tools/test_student.png"
DEFAULT_TAGS = "ai_tools/expanded_tags_taxonomy.json"
DEFAULT_IMAGE_SIZE = 256
MINIMUM_SCORE = 0.16
DISPLAY_SCORE_GAP = 0.04
NMS_THRESHOLD = 0.92
BLOCKED_TAGS = {"套路", "未婚妻", "字幕", "房主", "采购员"}


@dataclass(frozen=True)
class TagEntry:
    tag: str
    category: str
    common_word_order: int
    vector: np.ndarray


@dataclass(frozen=True)
class TagMatch:
    entry: TagEntry
    score: float


def parse_args():
    parser = argparse.ArgumentParser(
        description="Compare desktop PyTorch MobileCLIP against the exact ONNX + taxonomy pipeline used on mobile."
    )
    parser.add_argument("image", nargs="?", default=DEFAULT_IMAGE)
    parser.add_argument("--onnx", default=DEFAULT_ONNX)
    parser.add_argument("--tags", default=DEFAULT_TAGS)
    parser.add_argument("--top-k", type=int, default=5)
    return parser.parse_args()


def l2_normalize(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if norm == 0 or np.isnan(norm):
        return vector.astype(np.float32, copy=False)
    return (vector / norm).astype(np.float32, copy=False)


def preprocess_for_mobile_onnx(image: Image.Image, image_size: int) -> np.ndarray:
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
    array = np.asarray(cropped, dtype=np.float32) / 255.0
    array = np.transpose(array, (2, 0, 1))
    return np.expand_dims(array, axis=0).astype(np.float32, copy=False)


def run_pytorch(image_path: str, image_size: int) -> np.ndarray:
    model, _, _ = mobileclip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=CHECKPOINT,
    )
    model.eval()
    image = Image.open(image_path)
    input_tensor = preprocess_for_mobile_onnx(image, image_size)
    tensor = torch.from_numpy(input_tensor)
    with torch.no_grad():
        features = model.image_encoder(tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze(0).cpu().numpy().astype(np.float32, copy=False)


def infer_onnx_image_size(onnx_path: str) -> int:
    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    input_shape = session.get_inputs()[0].shape
    if len(input_shape) < 4 or not isinstance(input_shape[2], int):
        return DEFAULT_IMAGE_SIZE
    return int(input_shape[2])


def run_onnx(image_path: str, onnx_path: str, image_size: int) -> np.ndarray:
    session = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    image = Image.open(image_path)
    input_tensor = preprocess_for_mobile_onnx(image, image_size)
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name
    output = session.run([output_name], {input_name: input_tensor})[0]
    return l2_normalize(np.asarray(output, dtype=np.float32).reshape(-1))


def load_tag_entries(path: str) -> list[TagEntry]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    entries = []
    for item in data:
        vector = l2_normalize(np.asarray(item["vector"], dtype=np.float32))
        entries.append(
            TagEntry(
                tag=item["tag"],
                category=item.get("category", "抽象与其他"),
                common_word_order=int(item.get("common_word_order", 10**9)),
                vector=vector,
            )
        )
    return entries


def dot(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.dot(left[: min(len(left), len(right))], right[: min(len(left), len(right))]))


def is_noisy(entry: TagEntry) -> bool:
    if entry.tag in BLOCKED_TAGS:
        return True
    if entry.category == "抽象与其他" and entry.common_word_order > 8000:
        return True
    if entry.category == "人物与群体":
        if entry.common_word_order > 6000:
            return True
        if len(entry.tag) >= 4 and entry.common_word_order > 2500:
            return True
    if entry.category == "活动与事件" and entry.common_word_order > 12000:
        return True
    return False


def sorted_candidates(matches: list[TagMatch]) -> list[TagMatch]:
    return sorted(
        matches,
        key=lambda match: (
            -float(f"{match.score:.2f}"),
            -len(match.entry.tag),
            match.entry.common_word_order,
            -match.score,
            match.entry.tag,
        ),
    )


def retrieve_matches(embedding: np.ndarray, entries: list[TagEntry], top_k: int) -> tuple[list[TagMatch], list[TagMatch]]:
    normalized = l2_normalize(embedding)
    ranked = sorted(
        (TagMatch(entry=entry, score=dot(normalized, entry.vector)) for entry in entries),
        key=lambda match: match.score,
        reverse=True,
    )
    selected = select_core_tags(ranked, top_k=top_k, filter_noisy=True)
    if not selected:
        selected = select_core_tags(ranked, top_k=top_k, filter_noisy=False)
    if not selected:
        selected = ranked[:top_k]
    return ranked, selected


def select_core_tags(ranked: list[TagMatch], top_k: int, filter_noisy: bool) -> list[TagMatch]:
    if not ranked:
        return []

    top_score = ranked[0].score
    display_threshold = max(MINIMUM_SCORE, top_score - DISPLAY_SCORE_GAP)
    candidates = []
    for match in ranked:
        if match.score < display_threshold:
            continue
        if filter_noisy and is_noisy(match.entry):
            continue
        candidates.append(match)
    candidates = sorted_candidates(candidates)

    selected: list[TagMatch] = []
    for candidate in candidates:
        redundant = False
        for existing in selected:
            if dot(candidate.entry.vector, existing.entry.vector) > NMS_THRESHOLD:
                redundant = True
                break
        if redundant:
            continue
        selected.append(candidate)
        if len(selected) >= top_k:
            break
    return selected


def print_embedding_preview(name: str, embedding: np.ndarray):
    prefix = ", ".join(f"{value:.6f}" for value in embedding[:5])
    print(f"{name} 前5维: [{prefix}]")


def print_matches(title: str, matches: list[TagMatch]):
    print(f"\n=== {title} ===")
    for index, match in enumerate(matches, start=1):
        print(
            f"{index:>2}. {match.entry.tag}\t{match.score:.6f}\t{match.entry.category}"
        )


def main():
    args = parse_args()
    entries = load_tag_entries(args.tags)
    image_size = infer_onnx_image_size(args.onnx)
    pytorch_embedding = run_pytorch(args.image, image_size)
    onnx_embedding = run_onnx(args.image, args.onnx, image_size)

    cosine = dot(pytorch_embedding, onnx_embedding)
    max_abs_diff = float(np.max(np.abs(pytorch_embedding - onnx_embedding)))
    mean_abs_diff = float(np.mean(np.abs(pytorch_embedding - onnx_embedding)))

    print(f"图片: {args.image}")
    print(f"ONNX: {args.onnx}")
    print(f"输入尺寸: {image_size}")
    print(f"标签库: {args.tags}")
    print(f"PyTorch vs Mobile ONNX cosine: {cosine:.8f}")
    print(f"PyTorch vs Mobile ONNX max_abs_diff: {max_abs_diff:.8f}")
    print(f"PyTorch vs Mobile ONNX mean_abs_diff: {mean_abs_diff:.8f}")
    print_embedding_preview("PyTorch", pytorch_embedding)
    print_embedding_preview("Mobile ONNX", onnx_embedding)

    pytorch_ranked, pytorch_selected = retrieve_matches(pytorch_embedding, entries, args.top_k)
    onnx_ranked, onnx_selected = retrieve_matches(onnx_embedding, entries, args.top_k)
    print_matches("PyTorch selected tags", pytorch_selected)
    print_matches("Mobile ONNX selected tags", onnx_selected)
    print_matches("PyTorch raw top tags", pytorch_ranked[:args.top_k])
    print_matches("Mobile ONNX raw top tags", onnx_ranked[:args.top_k])


if __name__ == "__main__":
    main()