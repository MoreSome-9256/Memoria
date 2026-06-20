param(
  [Parameter(Mandatory = $true)][string]$ApiUrl,
  [string]$IdToken = "",
  [switch]$RunPaidTests
)

$ErrorActionPreference = "Stop"

$baseUrl = $ApiUrl.TrimEnd("/")

Write-Host "Checking unauthenticated request is rejected by the authorizer."
try {
  Invoke-RestMethod -Method Get -Uri "$baseUrl/v1/amap/regeo?location=116.397428,39.90923" | Out-Null
  throw "Unauthenticated request unexpectedly succeeded."
} catch {
  $statusCode = $_.Exception.Response.StatusCode.value__
  if ($statusCode -notin @(401, 403)) {
    throw
  }
  Write-Host "Unauthenticated request rejected with HTTP $statusCode."
}

if (-not $IdToken) {
  Write-Host "No -IdToken supplied. Skipping authenticated upstream tests."
  exit 0
}

$headers = @{ Authorization = "Bearer $IdToken" }

Write-Host "Checking authenticated Amap proxy."
$amap = Invoke-RestMethod `
  -Method Get `
  -Uri "$baseUrl/v1/amap/regeo?location=116.397428,39.90923&extensions=base&coordsys=gps" `
  -Headers $headers
Write-Host "Amap status: $($amap.status)"

if ($RunPaidTests) {
  Write-Host "Checking authenticated LLM proxy. This may incur provider cost."
  $body = @{
    messages = @(
      @{ role = "user"; content = "Reply with only the word ok." }
    )
    temperature = 0
    max_tokens = 4
  } | ConvertTo-Json -Depth 10

  $llm = Invoke-RestMethod `
    -Method Post `
    -Uri "$baseUrl/v1/llm/chat/completions" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body
  Write-Host "LLM response id: $($llm.id)"
}

Write-Host "Proxy smoke tests completed."
