param(
    [Parameter(Mandatory = $true)]
    [string]$LlamaServerPath,

    [Parameter(Mandatory = $true)]
    [string]$ModelPath,

    [Parameter(Mandatory = $true)]
    [string]$MmprojPath,

    [int]$Port = 8080,
    [int]$Threads = 8,
    [int]$ContextSize = 4096,
    [int]$GpuLayers = 0,
    [switch]$NoMmap
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingPath {
    param([string]$PathValue, [string]$Label)

    $resolved = Resolve-Path -LiteralPath $PathValue -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path)) {
        throw "$Label does not exist: $PathValue"
    }
    return $resolved.Path
}

$server = Resolve-ExistingPath -PathValue $LlamaServerPath -Label 'llama-server executable'
$model = Resolve-ExistingPath -PathValue $ModelPath -Label 'GGUF model'
$mmproj = Resolve-ExistingPath -PathValue $MmprojPath -Label 'mmproj file'

$args = @(
    '-m', $model,
    '--mmproj', $mmproj,
    '--host', '127.0.0.1',
    '--port', $Port,
    '--threads', $Threads,
    '--ctx-size', $ContextSize,
    '--no-webui'
)

if ($GpuLayers -gt 0) {
    $args += @('-ngl', $GpuLayers)
}

if ($NoMmap.IsPresent) {
    $args += '--no-mmap'
}

Write-Host 'Starting llama-server with:' -ForegroundColor Cyan
Write-Host "  server : $server"
Write-Host "  model  : $model"
Write-Host "  mmproj : $mmproj"
Write-Host "  port   : $Port"
Write-Host ''
Write-Host 'Stop the server with Ctrl+C after verification.' -ForegroundColor Yellow
Write-Host ''

& $server @args
