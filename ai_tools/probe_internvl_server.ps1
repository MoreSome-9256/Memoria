param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [string]$ServerUrl = 'http://127.0.0.1:8080/v1/chat/completions',
    [string]$Prompt = 'Describe this image in Chinese and list the 3 most certain visual facts.',
    [string]$Model = 'local-model',
    [int]$MaxTokens = 256,
    [double]$Temperature = 0.2
)

$ErrorActionPreference = 'Stop'

$resolvedImage = (Resolve-Path -LiteralPath $ImagePath -ErrorAction Stop).Path
$imageBytes = [System.IO.File]::ReadAllBytes($resolvedImage)
$imageExtension = [System.IO.Path]::GetExtension($resolvedImage).ToLowerInvariant()

$mimeType = switch ($imageExtension) {
    '.png' { 'image/png' }
    '.webp' { 'image/webp' }
    default { 'image/jpeg' }
}

$base64Image = [Convert]::ToBase64String($imageBytes)
$dataUrl = "data:$mimeType;base64,$base64Image"

$payload = @{
    model = $Model
    messages = @(
        @{
            role = 'user'
            content = @(
                @{
                    type = 'text'
                    text = $Prompt
                },
                @{
                    type = 'image_url'
                    image_url = @{
                        url = $dataUrl
                    }
                }
            )
        }
    )
    max_tokens = $MaxTokens
    temperature = $Temperature
    stream = $false
}

$response = Invoke-RestMethod `
    -Method Post `
    -Uri $ServerUrl `
    -ContentType 'application/json' `
    -Body ($payload | ConvertTo-Json -Depth 8)

if ($null -eq $response.choices -or $response.choices.Count -eq 0) {
    throw 'Server returned no choices.'
}

$content = $response.choices[0].message.content
Write-Host ''
Write-Host '=== Model Response ===' -ForegroundColor Green
Write-Host $content
