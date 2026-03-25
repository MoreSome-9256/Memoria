# Local Qwen3.5 Model Asset

This project uses a single GGUF file for local Qwen3.5-0.8B inference.
No separate mmproj file is required by project configuration.

## Default file path

Put one model file in this folder before building APK:

- assets/local_vlm/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf

The app bundles it into APK and extracts it on first run.

## Verified source and quantizer

- Official base model: Qwen/Qwen3.5-0.8B
- Recommended GGUF quantized publisher: bartowski
- Quantized repo: bartowski/Qwen_Qwen3.5-0.8B-GGUF

## How to choose quantization

- Default for mobile: Q4_K_M (best balance of memory/speed/quality)
- Lower memory fallback: Q3_K_M
- Better quality on high-end phones: Q5_K_M

## Download command (Hugging Face CLI)

```bash
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF Qwen_Qwen3.5-0.8B-Q4_K_M.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
```

Optional fallback model:

```bash
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF Qwen_Qwen3.5-0.8B-Q3_K_M.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
```

## Runtime overrides

Override bundled asset filename:

- LOCAL_QWEN35_08B_GGUF_ASSET=assets/local_vlm/your-model-file.gguf

Bypass bundled asset and load an absolute local file path:

- LOCAL_QWEN35_08B_GGUF_PATH
