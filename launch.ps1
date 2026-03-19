#!/usr/bin/env pwsh
# read device id from adb list
$deviceId = (adb devices | Select-String -Pattern "device$").ToString().Split("`t")[0]
# Write-Host "Found device: $deviceId"
if (-not $deviceId) {
    Write-Host "No device found. Please connect a device and try again."
    exit 1
}

# launch the app on the device
flutter run -d $deviceId --dart-define=LLM_BASE_URL=https://api.deepseek.com/v1 --dart-define=LLM_API_PATH=/chat/completions --dart-define=LLM_MODEL=deepseek-chat --dart-define=LLM_API_KEY=sk-c4d0cef54dae4ec4a57de1c811c67849 --dart-define=AMAP_WEB_KEY=7fe01f8a449b2aac28068feac9177316