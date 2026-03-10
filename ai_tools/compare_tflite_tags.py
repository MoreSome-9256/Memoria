import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
import torch
import mobileclip
import tensorflow as tf


MODEL_NAME = "mobileclip_s2"
CHECKPOINT = "checkpoints/mobileclip_s2.pt"
TAGS_FILE = "ai_tools/expanded_tags_vectors.json"
IMAGE_SIZE = 224
MEAN = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
STD = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)


def load_tag_vectors(path: str):
    with open(path, "r", encoding="utf-8") as file:
        data = json.load(file)
    tags = [item["tag"] for item in data]
    vectors = torch.tensor([item["vector"] for item in data], dtype=torch.float32)
    vectors = vectors / vectors.norm(dim=-1, keepdim=True)
    return tags, vectors


def preprocess_for_tflite(image: Image.Image) -> np.ndarray:
    width, height = image.size
    scale = IMAGE_SIZE / min(width, height)
    resized = image.resize((round(width * scale), round(height * scale)), Image.Resampling.BICUBIC)
    left = (resized.width - IMAGE_SIZE) // 2
    top = (resized.height - IMAGE_SIZE) // 2
    cropped = resized.crop((left, top, left + IMAGE_SIZE, top + IMAGE_SIZE))
    array = np.asarray(cropped, dtype=np.float32) / 255.0
    array = (array - MEAN) / STD
    return np.expand_dims(array, axis=0)


def l2_normalize(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if norm == 0 or np.isnan(norm):
        return vector
    return vector / norm


def run_pytorch(image_path: str):
    model, _, preprocess = mobileclip.create_model_and_transforms(
        MODEL_NAME, pretrained=CHECKPOINT
    )
    model.eval()
    image = Image.open(image_path).convert("RGB")
    tensor = preprocess(image).unsqueeze(0)
    with torch.no_grad():
        features = model.encode_image(tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze(0).cpu().numpy()


def run_tflite(model_path: str, image_path: str):
    interpreter = tf.lite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]
    image = Image.open(image_path).convert("RGB")
    input_tensor = preprocess_for_tflite(image).astype(input_details["dtype"])
    interpreter.set_tensor(input_details["index"], input_tensor)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details["index"])[0].astype(np.float32)
    return l2_normalize(output)


def print_top_tags(name: str, embedding: np.ndarray, tags, tag_vectors: torch.Tensor, top_k: int):
    embedding_tensor = torch.tensor(embedding, dtype=torch.float32)
    similarities = tag_vectors @ embedding_tensor
    top_values, top_indices = similarities.topk(top_k)
    print(f"\n=== {name} ===")
    for rank, (value, index) in enumerate(zip(top_values.tolist(), top_indices.tolist()), start=1):
        print(f"{rank:>2}. {tags[index]}\t{value:.4f}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--tflite", required=True)
    parser.add_argument("--top-k", type=int, default=10)
    args = parser.parse_args()

    tags, tag_vectors = load_tag_vectors(TAGS_FILE)
    pytorch_embedding = run_pytorch(args.image)
    tflite_embedding = run_tflite(args.tflite, args.image)

    cosine = float(np.dot(pytorch_embedding, tflite_embedding))
    print(f"PyTorch vs TFLite embedding cosine: {cosine:.6f}")
    print_top_tags("PyTorch", pytorch_embedding, tags, tag_vectors, args.top_k)
    print_top_tags("TFLite", tflite_embedding, tags, tag_vectors, args.top_k)


if __name__ == "__main__":
    main()