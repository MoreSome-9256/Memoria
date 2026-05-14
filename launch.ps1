#!/usr/bin/env pwsh
# Usage:
#   ./launch.ps1 dev
#   ./launch.ps1 prod emulator-5554

param(
    [string]$Profile = "dev",
    [string]$DeviceId = ""
)

$profileFile = "config/profiles/$Profile.json"
if (-not (Test-Path $profileFile)) {
    Write-Host "Profile file not found: $profileFile"
    Write-Host "Create it from template: config/profiles/dev.example.json"
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
# set env:FLUTTER_STORAGE_BASE_URL="https://mirrors.cernet.edu.cn/flutter"
$env:FLUTTER_STORAGE_BASE_URL = "https://mirrors.nju.edu.cn/flutter"
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
# launch the app on the device
flutter run -d $DeviceId --dart-define-from-file=$profileFile
