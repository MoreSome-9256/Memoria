# MobileViCLIP Small migration

This migration uses `ai_tools/.venv` only. The source checkpoint is expected at
`~/Downloads/mobileviclip_small.pt`, and the upstream architecture is expected
under `ai_tools/vendor/mobileviclip`.

Run:

```powershell
ai_tools\.venv\Scripts\python.exe ai_tools\export_mobileviclip_small.py
```

The script exports `assets/mobileviclip/small/mobileviclip_small.onnx`, attempts
`assets/mobileviclip/small/mobileviclip_small.mlpackage`, verifies ONNX Runtime
CPU, and writes:

- `assets/mobileviclip/small/mobileviclip_small_benchmark.json`
- `assets/mobileviclip/small/mobileviclip_small_metadata.json`

TFLite is intentionally reported as unavailable in this Windows CPython 3.14
environment when TensorFlow or the AI Edge converter cannot be installed. The
LiteRT runtime can be installed, but it cannot generate a `.tflite` model by
itself.

Core ML conversion is attempted with `coremltools`. Windows can create the
package but cannot execute Core ML, so iOS accuracy and latency must be measured
on device.
