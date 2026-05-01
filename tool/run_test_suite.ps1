[CmdletBinding()]
param(
  [switch]$IncludeLive,
  [switch]$PubGet
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Invoke-TestStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command
  )

  Write-Host ""
  Write-Host "==> $Name"
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

if ($PubGet) {
  Invoke-TestStep "flutter pub get" {
    flutter pub get
  }
}

$pubFlag = if ($PubGet) { '--pub' } else { '--no-pub' }

$splitAnalyzeTargets = @(
  'lib/view/pages/album_page.dart',
  'lib/view/pages/welcome_page.dart',
  'test/view/album_page_split_contract_test.dart',
  'test/view/album_page_split_compile_test.dart'
)

Invoke-TestStep "analyze split page targets" {
  flutter analyze `
    --no-fatal-infos `
    --no-fatal-warnings `
    $pubFlag `
    @splitAnalyzeTargets
}

Invoke-TestStep "run stable test suite" {
  flutter test `
    $pubFlag `
    --reporter expanded `
    test/all_tests.dart
}

if ($IncludeLive) {
  Invoke-TestStep "run live LLM test" {
    flutter test `
      $pubFlag `
      --reporter expanded `
      test/service/llm_service_live_test.dart
  }
} else {
  Write-Host ""
  Write-Host "Skipped live LLM test. Pass -IncludeLive to run it."
}
