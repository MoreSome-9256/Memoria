import argparse
import os
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image
import torch
import torch.nn as nn

REPO_ROOT = Path(__file__).resolve().parent.parent
VENDORED_REPO_ROOT = REPO_ROOT / 'third_party' / 'ncnn_mobileclip'
if str(VENDORED_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(VENDORED_REPO_ROOT))

import mobileclip  # type: ignore
import ncnn  # type: ignore
import pnnx  # type: ignore


DEFAULT_MODEL_NAME = 'mobileclip_s2'
DEFAULT_CHECKPOINT_DIR = REPO_ROOT / 'checkpoints'
DEFAULT_OUTPUT_DIR = REPO_ROOT / 'build' / 'mobileclip_s2_export'
DEFAULT_ASSET_DIR = REPO_ROOT / 'assets' / 'ncnn' / 'mobileclip_s2'
DEFAULT_IMAGE_PATH = REPO_ROOT / 'ai_tools' / 'test_youleyuan.png'


class ClipImageEncoder(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.image_encoder = model.image_encoder

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.image_encoder(x)


class ClipTextEncoder(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.embedding_layer = model.text_encoder.embedding_layer
        self.positional_embedding = model.text_encoder.positional_embedding
        self.embedding_dropout = model.text_encoder.embedding_dropout
        self.transformer = model.text_encoder.transformer
        self.final_layer_norm = model.text_encoder.final_layer_norm
        self.projection_layer = model.text_encoder.projection_layer
        self.causal_masking = model.text_encoder.causal_masking

    def build_attention_mask(self, context_length: int, batch_size: int) -> torch.Tensor:
        mask = torch.empty(context_length, context_length)
        mask.fill_(float('-inf'))
        mask.triu_(1)
        mask = mask.unsqueeze(0)
        mask = mask.expand(batch_size, -1, -1)
        return mask

    def forward(self, text_tokens: torch.Tensor, return_all_tokens: bool = True) -> torch.Tensor:
        token_emb = self.embedding_layer(text_tokens)
        seq_len = token_emb.shape[1]
        if self.positional_embedding is not None:
            token_emb = token_emb + self.positional_embedding(seq_len).to(token_emb.dtype)
        token_emb = self.embedding_dropout(token_emb)

        if self.causal_masking:
            attn_mask = self.build_attention_mask(
                context_length=text_tokens.shape[1],
                batch_size=text_tokens.shape[0],
            )
            attn_mask = attn_mask.to(device=token_emb.device, dtype=token_emb.dtype)
            for layer in self.transformer:
                token_emb = layer(token_emb, attn_mask=attn_mask)
        else:
            for layer in self.transformer:
                token_emb = layer(token_emb)

        token_emb = self.final_layer_norm(token_emb)

        if return_all_tokens:
            return token_emb

        token_emb = token_emb[
            torch.arange(text_tokens.shape[0]), text_tokens.argmax(dim=-1)
        ]
        token_emb = token_emb @ self.projection_layer
        return token_emb


class ClipProjection(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.projection_layer = model.text_encoder.projection_layer

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return x @ self.projection_layer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Export MobileCLIP to NCNN directly using the vendored futz12/ncnn_mobileclip implementation.',
    )
    parser.add_argument('--model-name', default=DEFAULT_MODEL_NAME)
    parser.add_argument('--checkpoint-dir', default=str(DEFAULT_CHECKPOINT_DIR))
    parser.add_argument('--output-dir', default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument('--asset-dir', default=str(DEFAULT_ASSET_DIR))
    parser.add_argument('--image-path', default=str(DEFAULT_IMAGE_PATH))
    parser.add_argument('--fp16', action='store_true')
    parser.add_argument('--skip-asset-copy', action='store_true')
    return parser.parse_args()


def ensure_supported_model(model_name: str) -> None:
    valid_models = [
        'mobileclip_s0',
        'mobileclip_s1',
        'mobileclip_s2',
        'mobileclip_b',
        'mobileclip_blt',
    ]
    if model_name not in valid_models:
        raise ValueError(f'Unsupported model name: {model_name}. Expected one of {valid_models}')


def load_test_image(image_path: Path) -> Image.Image:
    if image_path.exists():
        return Image.open(image_path).convert('RGB')

    test_img = np.zeros((256, 256, 3), dtype=np.uint8)
    test_img[:128, :128] = [255, 0, 0]
    return Image.fromarray(test_img)


def copy_runtime_assets(output_dir: Path, asset_dir: Path) -> None:
    asset_dir.mkdir(parents=True, exist_ok=True)
    for name in ('image_encoder.ncnn.param', 'image_encoder.ncnn.bin'):
        shutil.copyfile(output_dir / name, asset_dir / name)


def export_with_futz12(model_name: str, checkpoint_dir: Path, output_dir: Path, image_path: Path, fp16: bool) -> None:
    ensure_supported_model(model_name)
    output_dir.mkdir(parents=True, exist_ok=True)

    checkpoint_path = checkpoint_dir / f'{model_name}.pt'
    if not checkpoint_path.exists():
        raise FileNotFoundError(f'Checkpoint not found: {checkpoint_path}')

    model, _, preprocess = mobileclip.create_model_and_transforms(
        model_name,
        pretrained=str(checkpoint_path),
    )
    tokenizer = mobileclip.get_tokenizer(model_name)
    model.eval()

    image = load_test_image(image_path)
    input_image = preprocess(image).unsqueeze(0)
    input_text = tokenizer(['Test'])
    input_embed = torch.ones((1, 1, 512), dtype=torch.float32)

    current_dir = Path.cwd()
    os.chdir(output_dir)
    try:
        image_encoder = ClipImageEncoder(model)
        pnnx.export(image_encoder, 'image_encoder.pt', input_image, fp16=fp16)

        text_encoder = ClipTextEncoder(model)
        pnnx.export(text_encoder, 'text_encoder.pt', input_text, fp16=fp16)

        projection_layer = ClipProjection(model)
        pnnx.export(projection_layer, 'projection_layer.pt', input_embed, fp16=fp16)

        print(f'模型已成功导出到: {output_dir}/')
        print(f'图像编码器输入尺寸: {input_image.shape}')
        print(f'文本编码器输入尺寸: {input_text.shape}')
        print(f'投影层输入尺寸: {input_embed.shape}')
        print('正在开始验证ncnn模型...')

        with ncnn.Net() as net:
            net.load_param('image_encoder.ncnn.param')
            net.load_model('image_encoder.ncnn.bin')
            with net.create_extractor() as ex:
                ex.input('in0', ncnn.Mat(input_image.squeeze(0).numpy()).clone())
                _, out0 = ex.extract('out0')
                out_image = torch.from_numpy(np.array(out0)).unsqueeze(0)

        mse_image = torch.mean((out_image - image_encoder(input_image).detach()) ** 2).item()
        print(f'图像编码器输出尺寸: {out_image.shape}')
        if mse_image >= 1e-4:
            raise RuntimeError(f'图像编码器验证失败，MSE: {mse_image:.12f}')
        print(f'图像编码器验证通过，MSE: {mse_image:.12f}')

        with ncnn.Net() as net:
            net.load_param('text_encoder.ncnn.param')
            net.load_model('text_encoder.ncnn.bin')
            with net.create_extractor() as ex:
                ex.input('in0', ncnn.Mat(input_text.numpy().astype(np.int32)).clone())
                _, out0 = ex.extract('out0')
                out_text = torch.from_numpy(np.array(out0)).unsqueeze(0)

        mse_text = torch.mean((out_text - text_encoder(input_text).detach()) ** 2).item()
        print(f'文本编码器输出尺寸: {out_text.shape}')
        if mse_text >= 1e-4:
            raise RuntimeError(f'文本编码器验证失败，MSE: {mse_text:.12f}')
        print(f'文本编码器验证通过，MSE: {mse_text:.12f}')

        with ncnn.Net() as net:
            net.load_param('projection_layer.ncnn.param')
            net.load_model('projection_layer.ncnn.bin')
            with net.create_extractor() as ex:
                ex.input('in0', ncnn.Mat(input_embed.numpy()).clone())
                _, out0 = ex.extract('out0')
                out_projection = torch.from_numpy(np.array(out0)).unsqueeze(0)

        mse_projection = torch.mean(
            (out_projection - projection_layer(input_embed).detach()) ** 2,
        ).item()
        print(f'投影层输出尺寸: {out_projection.shape}')
        if mse_projection >= 1e-4:
            raise RuntimeError(f'投影层验证失败，MSE: {mse_projection:.12f}')
        print(f'投影层验证通过，MSE: {mse_projection:.12f}')
        print('ncnn模型验证完成。')
    finally:
        os.chdir(current_dir)


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    asset_dir = Path(args.asset_dir)
    checkpoint_dir = Path(args.checkpoint_dir)
    image_path = Path(args.image_path)

    export_with_futz12(
        model_name=args.model_name,
        checkpoint_dir=checkpoint_dir,
        output_dir=output_dir,
        image_path=image_path,
        fp16=args.fp16,
    )

    if not args.skip_asset_copy:
        copy_runtime_assets(output_dir, asset_dir)
        print(f'已同步 image encoder 运行时模型到: {asset_dir}')


if __name__ == '__main__':
    main()