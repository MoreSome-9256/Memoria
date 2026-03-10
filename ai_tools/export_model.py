import torch
import torch.nn as nn
import mobileclip
import onnx
from onnxsim import simplify
import os
import argparse

# 🌟 神奇的猴子补丁 (Monkey Patch) 🌟
# 伪造一个零件，骗过 onnx_graphsurgeon 的强制检查
if not hasattr(onnx.helper, 'float32_to_bfloat16'):
    onnx.helper.float32_to_bfloat16 = lambda x: x

from onnx2tf import convert  # 🌟 直接引入 onnx2tf 的 Python API


class QuickGELU(nn.Module):
    def forward(self, x):
        return x * torch.sigmoid(1.702 * x)


def build_activation_replacement(name: str) -> nn.Module:
    normalized = name.lower()
    if normalized == "quickgelu":
        return QuickGELU()
    if normalized == "silu":
        return nn.SiLU()
    raise ValueError(f"不支持的激活函数替换: {name}")


def replace_gelu_modules(module: nn.Module, activation_name: str) -> int:
    replacement_count = 0
    for child_name, child in module.named_children():
        if isinstance(child, nn.GELU):
            setattr(module, child_name, build_activation_replacement(activation_name))
            replacement_count += 1
            continue
        replacement_count += replace_gelu_modules(child, activation_name)
    return replacement_count

def export_mobileclip_to_tflite(
    output_folder: str = "saved_model",
    reuse_existing_onnx: bool = False,
    activation: str = "quickgelu",
):
    model_name = "mobileclip_s2"
    onnx_path = "mobileclip_vision.onnx"

    if not reuse_existing_onnx:
        # 1. 加载预训练模型
        print(f"--- 正在加载 {model_name} ---")
        model, _, _ = mobileclip.create_model_and_transforms(model_name, pretrained="checkpoints/mobileclip_s2.pt")
        vision_model = model.image_encoder  # 苹果官方的正确属性名
        replaced_count = replace_gelu_modules(vision_model, activation)
        print(f"--- 已将 {replaced_count} 个 GELU 替换为 {activation} ---")
        vision_model.eval()

        # 2. 导出为 ONNX
        dummy_input = torch.randn(1, 3, 224, 224)
        print("--- 正在导出 ONNX ---")
        torch.onnx.export(
            vision_model,
            dummy_input,
            onnx_path,
            export_params=True,
            opset_version=18,  # 使用推荐的 18 版本
            do_constant_folding=True,
            input_names=['input'],
            output_names=['output'],
        )

        # 3. ONNX 图优化
        print("--- 正在进行图优化 ---")
        onnx_model = onnx.load(onnx_path)
        model_simp, check = simplify(onnx_model)
        assert check, "Simplified ONNX model could not be validated"
        onnx.save(model_simp, onnx_path)
    else:
        if not os.path.exists(onnx_path):
            raise FileNotFoundError(f"未找到现有 ONNX 文件: {onnx_path}")
        print(f"--- 复用现有 ONNX: {onnx_path} ---")

    # 4. ONNX 转 TensorFlow 并生成 TFLite
    print("--- 正在转换为 TFLite ---")
    # 🌟 使用 Python API 转换，无视任何系统的环境变量配置问题！
    convert(
        input_onnx_file_path=onnx_path,
        output_folder_path=output_folder,
        copy_onnx_input_output_names_to_tflite=True,
        non_verbose=True  # 隐藏过多的底层转换日志，保持清爽
    )

    print(f"--- 转换大功告成！请去 {output_folder} 文件夹下查看生成的 .tflite 模型 ---")


def _parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-folder",
        default="saved_model",
        help="TFLite 导出目录",
    )
    parser.add_argument(
        "--reuse-existing-onnx",
        action="store_true",
        help="跳过 PyTorch -> ONNX，直接复用现有 mobileclip_vision.onnx",
    )
    parser.add_argument(
        "--activation",
        default="quickgelu",
        choices=["quickgelu", "silu"],
        help="导出前将模型中的 GELU 替换为哪种端侧友好激活",
    )
    return parser.parse_args()

if __name__ == "__main__":
    args = _parse_args()
    export_mobileclip_to_tflite(
        output_folder=args.output_folder,
        reuse_existing_onnx=args.reuse_existing_onnx,
        activation=args.activation,
    )