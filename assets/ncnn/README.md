Place exported MobileCLIP NCNN assets here.

Expected layout:

- assets/ncnn/mobileclip_s2/image_encoder.ncnn.param
- assets/ncnn/mobileclip_s2/image_encoder.ncnn.bin
- assets/ncnn/mobileclip_s2/text_encoder.ncnn.param
- assets/ncnn/mobileclip_s2/text_encoder.ncnn.bin
- assets/ncnn/mobileclip_s2/projection_layer.ncnn.param
- assets/ncnn/mobileclip_s2/projection_layer.ncnn.bin

These paths match lib/service/ncnn_mobileclip_native_service.dart.

Source of truth:

- Download the author-provided package from:
- https://drive.google.com/file/d/1WFQEwWxUCFhDASbXv7fAlXUHn1BnVGGI/view
- Keep the original download under third_party/mobileclip_s2_export/
- Sync the six model files into assets/ncnn/mobileclip_s2/