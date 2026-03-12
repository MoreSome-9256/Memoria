import argparse
from pathlib import Path

import mobileclip
import numpy as np
import torch
from PIL import Image, ImageOps


MODEL_NAME = 'mobileclip_s2'
DEFAULT_CHECKPOINT = 'checkpoints/mobileclip_s2.pt'
DEFAULT_IMAGE_SIZE = 256
DEFAULT_IMAGES = [
    'ai_tools/test_student.png',
    'ai_tools/test1.png',
    'ai_tools/test_youleyuan.png',
]
DEFAULT_TEXTS = [
    'student',
    'steamed bun',
    'amusement park',
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Compare MobileCLIP image embeddings against English text embeddings.'
    )
    parser.add_argument('--checkpoint', default=DEFAULT_CHECKPOINT)
    parser.add_argument('--image-size', type=int, default=DEFAULT_IMAGE_SIZE)
    parser.add_argument('--images', nargs='*', default=DEFAULT_IMAGES)
    parser.add_argument('--texts', nargs='*', default=DEFAULT_TEXTS)
    return parser.parse_args()


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


def load_model(checkpoint: str):
    model, _, _ = mobileclip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=checkpoint,
    )
    tokenizer = mobileclip.get_tokenizer(MODEL_NAME)
    model.eval()
    return model, tokenizer


def encode_image(model: torch.nn.Module, image_path: str, image_size: int) -> np.ndarray:
    image = Image.open(image_path)
    input_tensor = torch.from_numpy(preprocess_for_mobile(image, image_size))
    with torch.no_grad():
        vector = model.encode_image(input_tensor, normalize=True)
    return vector.squeeze(0).cpu().numpy().astype(np.float32, copy=False)


def encode_text(model: torch.nn.Module, tokenizer, text: str) -> np.ndarray:
    tokens = tokenizer(text)
    if tokens.ndim == 1:
        tokens = tokens.unsqueeze(0)
    with torch.no_grad():
        vector = model.encode_text(tokens, normalize=True)
    return vector.squeeze(0).cpu().numpy().astype(np.float32, copy=False)


def main() -> None:
    args = parse_args()
    model, tokenizer = load_model(args.checkpoint)

    image_vectors = {
        image_path: encode_image(model, image_path, args.image_size)
        for image_path in args.images
    }
    text_vectors = {
        text: encode_text(model, tokenizer, text)
        for text in args.texts
    }

    print(f'checkpoint: {Path(args.checkpoint)}')
    print('image-text cosine matrix:')
    header = ['image'] + args.texts
    print('\t'.join(header))
    for image_path in args.images:
        row = [image_path]
        image_vector = image_vectors[image_path]
        for text in args.texts:
            cosine = float(np.dot(image_vector, text_vectors[text]))
            row.append(f'{cosine:.6f}')
        print('\t'.join(row))

    print('\ntext-text cosine matrix:')
    print('\t'.join(['text'] + args.texts))
    for left_text in args.texts:
        row = [left_text]
        left_vector = text_vectors[left_text]
        for right_text in args.texts:
            cosine = float(np.dot(left_vector, text_vectors[right_text]))
            row.append(f'{cosine:.6f}')
        print('\t'.join(row))

    print('\nimage top text match:')
    for image_path in args.images:
        ranked = sorted(
            ((text, float(np.dot(image_vectors[image_path], text_vectors[text]))) for text in args.texts),
            key=lambda item: item[1],
            reverse=True,
        )
        print(f'{image_path}\tbest={ranked[0][0]}\tcosine={ranked[0][1]:.6f}\tfull={ranked}')


if __name__ == '__main__':
    main()