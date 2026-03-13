---
library_name: transformers.js
tags:
  - clip
  - vision
  - onnx
  - transformers.js
  - image-feature-extraction
license: apple-amlr
base_model: apple/MobileCLIP2-S2
pipeline_tag: image-feature-extraction
---

# MobileCLIP2 ONNX

ONNX exports of [Apple's MobileCLIP2](https://github.com/apple/ml-mobileclip) models for use with [Transformers.js](https://huggingface.co/docs/transformers.js).

## Available Models

| Model | Vision Size | Embed Dim | Image Size | Use Case |
|-------|-------------|-----------|------------|----------|
| **S0** | 43 MB | 512 | 256x256 | Ultra-lightweight, fastest inference |
| **S2** | 136 MB | 512 | 256x256 | Good balance of size and quality |
| **B** | 330 MB | 512 | 224x224 | Higher quality, ViT-based |
| **L-14** | 1.1 GB | 768 | 224x224 | Highest quality, largest |

All models include both vision and text encoders.

## Usage with Transformers.js

```javascript
import { CLIPVisionModelWithProjection, AutoProcessor, RawImage } from '@huggingface/transformers';

// Choose your model size: 's0', 's2', 'b', or 'l14'
const modelSize = 's2';

// Load model and processor
const model = await CLIPVisionModelWithProjection.from_pretrained('plhery/mobileclip2-onnx', {
  device: 'webgpu', // or 'wasm'
  dtype: 'fp32',
  model_file_name: `onnx/${modelSize}/vision_model`,
});
const processor = await AutoProcessor.from_pretrained('plhery/mobileclip2-onnx', {
  config_file_name: `onnx/${modelSize}/preprocessor_config.json`,
});

// Process an image
const image = await RawImage.read('path/to/image.jpg');
const inputs = await processor([image]);

// Get embeddings (L2-normalized)
const outputs = await model({ pixel_values: inputs.pixel_values });
const embeddings = outputs.image_embeds.normalize(2, -1);
```

## File Structure

```
onnx/
  s0/
    vision_model.onnx
    text_model.onnx
    config.json
    preprocessor_config.json
  s2/
    ...
  b/
    ...
  l14/
    ...
```

## Technical Notes

- Outputs are **unnormalized** embeddings; L2-normalize before computing cosine similarities
- Text input: token IDs shaped `[batch, 77]` (CLIP BPE vocab size 49408)
- Preprocessing: `image_mean=(0,0,0)`, `image_std=(1,1,1)` for all variants

## Local Conversion

```bash
./setup_open_clip.sh
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Convert specific model (default: S2)
python convert_mobileclip2_b_to_onnx.py --model-name MobileCLIP2-S0 --out-dir onnx/s0 --skip-fp16
python convert_mobileclip2_b_to_onnx.py --model-name MobileCLIP2-B --out-dir onnx/b --skip-fp16
```

## License

Apple Sample Code License (apple-amlr), following the original [MobileCLIP license](https://huggingface.co/apple/MobileCLIP2-S2).

## Acknowledgments

- Original models by [Apple ML Research](https://github.com/apple/ml-mobileclip)
- Converted for [BestPick](https://github.com/PLhery/BestPick) photo organizer
