import argparse
from pathlib import Path

import mobileclip
import onnx
import torch


MODEL_NAME = "mobileclip_s2"
CHECKPOINT = "checkpoints/mobileclip_s2.pt"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Export a parity-correct MobileCLIP ONNX for desktop and Android mobile use."
    )
    parser.add_argument(
        "--onnx-output",
        default="mobileclip_vision.onnx",
        help="Path for the primary exported ONNX file.",
    )
    parser.add_argument(
        "--ir9-output",
        default="mobileclip_vision_ir9.onnx",
        help="Path for the Android-compatible IR9 ONNX file.",
    )
    parser.add_argument(
        "--skip-ir9",
        action="store_true",
        help="Only export the primary ONNX file.",
    )
    parser.add_argument(
        "--image-size",
        type=int,
        default=256,
        help="Square input size used by the exported vision encoder.",
    )
    return parser.parse_args()


def export_mobileclip_onnx(
    onnx_output: str,
    ir9_output: str | None,
    image_size: int,
):
    model, _, _ = mobileclip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=CHECKPOINT,
    )
    vision = model.image_encoder.eval()
    dummy_input = torch.randn(1, 3, image_size, image_size)

    print(f"--- exporting parity ONNX to {onnx_output} ---")
    torch.onnx.export(
        vision,
        dummy_input,
        onnx_output,
        export_params=True,
        opset_version=18,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["output"],
        dynamo=True,
    )

    if ir9_output is None:
        return

    print(f"--- writing Android IR9 ONNX to {ir9_output} ---")
    model_proto = onnx.load(onnx_output)
    model_proto.ir_version = 9
    onnx.save(model_proto, ir9_output)


def main():
    args = parse_args()
    onnx_output = str(Path(args.onnx_output))
    ir9_output = None if args.skip_ir9 else str(Path(args.ir9_output))
    export_mobileclip_onnx(onnx_output, ir9_output, args.image_size)


if __name__ == "__main__":
    main()