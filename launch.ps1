#!/usr/bin/env pwsh
# Usage:
#   ./launch.ps1 proxy
#   ./launch.ps1 prod emulator-5554

param(
    [string]$Profile = "proxy",
    [string]$DeviceId = ""
)

$profileFile = "config/profiles/$Profile.json"
if (-not (Test-Path $profileFile)) {
    Write-Host "Profile file not found: $profileFile"
    Write-Host "Use config/profiles/proxy.json or create a private profile."
    exit 1
}

if (-not $DeviceId) {
    $deviceLine = (adb devices | Select-String -Pattern "`tdevice$").ToString()
    if ($deviceLine) {
        $DeviceId = $deviceLine.Split("`t")[0]
    }
}

if (-not $DeviceId) {
    Write-Host "No device found. Please connect a device or pass one as the 2nd arg."
    exit 1
}

Write-Host "Using profile: $Profile"
Write-Host "Using device : $DeviceId"
# Use the Flutter China mirror for engine Maven artifacts. Some university
# mirrors can lag new engine hashes and fail resolving flutter_embedding_debug.
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
flutter pub get
dart run build_runner build
# launch the app on the device
flutter run -d $DeviceId --dart-define-from-file=$profileFile
