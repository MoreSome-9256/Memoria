# Local Qwen3.5 Model Assets

This project uses two GGUF files for local Qwen3.5-0.8B multimodal inference:

- one model file
- one mmproj file

## Default file paths

Put both files in this folder before building APK:

- assets/local_vlm/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf
- assets/local_vlm/mmproj-Qwen_Qwen3.5-0.8B-f16.gguf

The app bundles it into APK and extracts it on first run.

## Verified source and quantizer

- Official base model: Qwen/Qwen3.5-0.8B
- Recommended GGUF quantized publisher: bartowski
- Quantized repo: bartowski/Qwen_Qwen3.5-0.8B-GGUF

## How to choose quantization

- Default for mobile: Q4_K_M (best balance of memory/speed/quality)
- Lower memory fallback: Q3_K_M
- Better quality on high-end phones: Q5_K_M

## Download commands (Hugging Face CLI)

```bash
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF Qwen_Qwen3.5-0.8B-Q4_K_M.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF mmproj-Qwen_Qwen3.5-0.8B-f16.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
```

Optional fallback model:

```bash
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF Qwen_Qwen3.5-0.8B-Q3_K_M.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
```

## Runtime overrides

Override bundled asset filename:

- LOCAL_QWEN35_08B_GGUF_ASSET=assets/local_vlm/your-model-file.gguf
- LOCAL_QWEN35_08B_MMPROJ_ASSET=assets/local_vlm/your-mmproj-file.gguf

Bypass bundled asset and load an absolute local file path:

- LOCAL_QWEN35_08B_GGUF_PATH
- LOCAL_QWEN35_08B_MMPROJ_PATH
