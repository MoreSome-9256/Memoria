#!/usr/bin/env pwsh
# Usage:
#   ./launch.ps1 dev
#   ./launch.ps1 prod emulator-5554

param(
    [string]$Profile = "dev",
    [string]$DeviceId = ""
)

function Ensure-IsarGenerated {
    $entityDir = "lib/models/entity"
    if (-not (Test-Path $entityDir)) {
        return
    }

    $entityFiles = Get-ChildItem -Path $entityDir -Filter "*.dart" -File |
        Where-Object { $_.Name -notlike "*.g.dart" }

    $missing = @()
    foreach ($file in $entityFiles) {
        $generated = Join-Path $entityDir ($file.BaseName + ".g.dart")
        if (-not (Test-Path $generated)) {
            $missing += $generated
        }
    }

    if ($missing.Count -eq 0) {
        return
    }

    Write-Host "Detected missing generated files:" -ForegroundColor Yellow
    foreach ($path in $missing) {
        Write-Host "  - $path" -ForegroundColor Yellow
    }

    Write-Host "Running build_runner to generate Isar code..." -ForegroundColor Cyan
    dart run build_runner build --delete-conflicting-outputs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "build_runner failed. Please check errors above." -ForegroundColor Red
        exit 1
    }
}

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

Ensure-IsarGenerated

# launch the app on the device
flutter run -d $DeviceId --no-enable-impeller --dart-define-from-file=$profileFile