import argparse
import json
from pathlib import Path

import mobileclip
import numpy as np
import torch
from PIL import Image, ImageOps


MODEL_NAME = 'mobileclip_s2'
CHECKPOINT = 'checkpoints/mobileclip_s2.pt'
DEFAULT_IMAGE_SIZE = 256
DEFAULT_IMAGES = [
    'ai_tools/test_student.png',
    'ai_tools/test1.png',
    'ai_tools/test_youleyuan.png',
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Dump MobileCLIP PT embeddings with the same preprocessing shape as the mobile path.'
    )
    parser.add_argument('images', nargs='*', default=DEFAULT_IMAGES)
    parser.add_argument('--checkpoint', default=CHECKPOINT)
    parser.add_argument('--image-size', type=int, default=DEFAULT_IMAGE_SIZE)
    parser.add_argument('--dump-json', default=None)
    return parser.parse_args()


def l2_normalize(vector: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(vector)
    if norm == 0 or np.isnan(norm):
        return vector.astype(np.float32, copy=False)
    return (vector / norm).astype(np.float32, copy=False)


def preprocess_for_mobile(image: Image.Image, image_size: int) -> np.ndarray:
    baked = ImageOps.exif_transpose(image).convert('RGB')
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


def load_model(checkpoint: str) -> torch.nn.Module:
    model, _, _ = mobileclip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=checkpoint,
    )
    model.eval()
    return model


def encode_image(model: torch.nn.Module, image_path: str, image_size: int) -> np.ndarray:
    image = Image.open(image_path)
    input_tensor = torch.from_numpy(preprocess_for_mobile(image, image_size))
    with torch.no_grad():
        features = model.image_encoder(input_tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    vector = features.squeeze(0).cpu().numpy().astype(np.float32, copy=False)
    return l2_normalize(vector)


def main() -> None:
    args = parse_args()
    model = load_model(args.checkpoint)
    report = []

    for image_path in args.images:
      vector = encode_image(model, image_path, args.image_size)
      entry = {
          'image': image_path,
          'dims': int(vector.shape[0]),
          'first16': [float(value) for value in vector[:16]],
          'vector': [float(value) for value in vector],
      }
      report.append(entry)
      print(f'image: {image_path}')
      print(f'dims: {entry["dims"]}')
      print('first16: [' + ', '.join(f'{value:.6f}' for value in vector[:16]) + ']')

    payload = {'results': report}
    if args.dump_json:
        dump_path = Path(args.dump_json)
        dump_path.write_text(json.dumps(payload, ensure_ascii=False), encoding='utf-8')
        print(f'json: {dump_path}')
    else:
        print('PT_VECTOR_JSON=' + json.dumps(payload, ensure_ascii=False))


if __name__ == '__main__':
    main()