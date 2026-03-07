import torch
import mobileclip
import onnx
from onnxsim import simplify
import os

# 🌟 神奇的猴子补丁 (Monkey Patch) 🌟
# 伪造一个零件，骗过 onnx_graphsurgeon 的强制检查
if not hasattr(onnx.helper, 'float32_to_bfloat16'):
    onnx.helper.float32_to_bfloat16 = lambda x: x

from onnx2tf import convert  # 🌟 直接引入 onnx2tf 的 Python API

def export_mobileclip_to_tflite():
    model_name = "mobileclip_s2"
    onnx_path = "mobileclip_vision.onnx"

    # 1. 加载预训练模型
    print(f"--- 正在加载 {model_name} ---")
    model, _, _ = mobileclip.create_model_and_transforms(model_name, pretrained="checkpoints/mobileclip_s2.pt")
    vision_model = model.image_encoder  # 苹果官方的正确属性名
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

    # 4. ONNX 转 TensorFlow 并生成 TFLite
    print("--- 正在转换为 TFLite ---")
    # 🌟 使用 Python API 转换，无视任何系统的环境变量配置问题！
    convert(
        input_onnx_file_path=onnx_path,
        output_folder_path="saved_model",
        copy_onnx_input_output_names_to_tflite=True,
        non_verbose=True  # 隐藏过多的底层转换日志，保持清爽
    )

    print(f"--- 转换大功告成！请去 saved_model 文件夹下查看生成的 .tflite 模型 ---")

if __name__ == "__main__":
    export_mobileclip_to_tflite()