# MobileViCLIP / MobileCLIP NCNN Notes

This file records the current conversion boundary so future work does not mix
up the three model families used by Memoria.

## Current facts

- MobileCLIP is the Apple image/text family used by the existing NCNN export
  path under `third_party/ncnn_mobileclip` and `ai_tools/export_mobileclip_ncnn.py`.
- MobileCLIP2 is the newer LiteRT/TFLite path exported under
  `third_party/mobileclip2_litert_export`; it is not the same graph as the
  MobileCLIP-S2 NCNN assets.
- `third_party/ncnn_mobileclip/mobileclip2_ncnn` is present, but should remain
  experimental until parity tests compare image/text embeddings against the
  XNNPACK LiteRT path on the same inputs and taxonomy prompts.
- MobileViCLIP is a video-text model built from an efficient MobileCLIP-style
  backbone. The current app asset is the video vision encoder ONNX file at
  `assets/mobileviclip/small/mobileviclip_small.onnx`.

## NCNN direction

1. Keep the existing `assets/ncnn/mobileclip_s2` image/text NCNN path separate
   from MobileCLIP2. Do not label those vectors as MobileCLIP2.
2. For MobileViCLIP, export the ONNX vision encoder through `onnx2ncnn`, then
   run `ncnnoptimize`. Validate tensor names, shape `[1, 8, 3, 256, 256]`, and
   output dimension `512` before adding it to the Flutter path.
3. Prefer fp16 storage/arithmetic first for Vulkan. Add int8 only after a
   calibration set proves parity against the ONNX path.
4. The native NCNN bridge already enables Vulkan when a device is available via
   `net.opt.use_vulkan_compute = true` in
   `android/app/src/main/cpp/vendored_mobileclip_image_encoder.cpp`.
5. Keep video vectors under `kVideoEmbeddingModelFamily`; do not mix them with
   `mobileclip_image_*` indices or with `PhotoEntity.imageEmbedding`.

## References checked

- Apple MobileCLIP / MobileCLIP2 repository:
  https://github.com/apple/ml-mobileclip
- MobileViCLIP repository:
  https://github.com/MCG-NJU/MobileViCLIP
- ncnn documentation:
  https://ncnn.readthedocs.io/en/latest/
- ncnn Vulkan notes:
  https://github.com/Tencent/ncnn/wiki/FAQ-ncnn-vulkan
