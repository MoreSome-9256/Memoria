param(
  [string]$StackName = "memoria-api-proxy-dev",
  [Parameter(Mandatory = $true)][string]$ConfigProfilePath,
  [string]$Region = "",
  [string]$Profile = "",
  [string]$ArtifactBucket = "",
  [string]$SecretName = "memoria/api-proxy/dev",
  [switch]$SkipSecretUpsert
)

$ErrorActionPreference = "Stop"

function Invoke-Aws {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

  $fullArgs = @()
  if ($Profile) {
    $fullArgs += @("--profile", $Profile)
  }
  if ($Region) {
    $fullArgs += @("--region", $Region)
  }
  $fullArgs += $Args
  & aws @fullArgs
  if ($LASTEXITCODE -ne 0) {
    throw "aws $($Args -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Test-AwsCommand {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

  $fullArgs = @()
  if ($Profile) {
    $fullArgs += @("--profile", $Profile)
  }
  if ($Region) {
    $fullArgs += @("--region", $Region)
  }
  $fullArgs += $Args
  & aws @fullArgs 2>$null | Out-Null
  return $LASTEXITCODE -eq 0
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Config file not found: $Path"
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-OptionalValue {
  param([object]$Object, [string]$Name, [string]$Default = "")

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $Default
  }
  return [string]$property.Value
}

Push-Location $PSScriptRoot\..
try {
  $config = Read-JsonFile -Path $ConfigProfilePath

  if (-not $Region) {
    $Region = Get-OptionalValue -Object $config -Name "AWS_REGION"
  }
  if (-not $Region) {
    $Region = (& aws configure get region).Trim()
  }
  if (-not $Region) {
    throw "AWS region is required. Set AWS_REGION in the profile or pass -Region."
  }

  $userPoolId = Get-OptionalValue -Object $config -Name "COGNITO_USER_POOL_ID"
  $appClientId = Get-OptionalValue -Object $config -Name "COGNITO_APP_CLIENT_ID"
  if (-not $userPoolId -or -not $appClientId) {
    throw "COGNITO_USER_POOL_ID and COGNITO_APP_CLIENT_ID are required."
  }

  $identityJson = Invoke-Aws sts get-caller-identity | Out-String
  $identity = $identityJson | ConvertFrom-Json
  $accountId = [string]$identity.Account
  Write-Host "Deploying stack '$StackName' to account $accountId, region $Region."

  if (-not $ArtifactBucket) {
    $ArtifactBucket = "$StackName-artifacts-$accountId-$Region".ToLowerInvariant()
  }

  $bucketExists = Test-AwsCommand s3api head-bucket --bucket $ArtifactBucket
  if (-not $bucketExists) {
    Write-Host "Creating artifact bucket $ArtifactBucket."
    if ($Region -eq "us-east-1") {
      Invoke-Aws s3api create-bucket --bucket $ArtifactBucket | Out-Null
    } else {
      Invoke-Aws s3api create-bucket `
        --bucket $ArtifactBucket `
        --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    }
  }

  $secretId = ""
  if ($SkipSecretUpsert) {
    if (Test-AwsCommand secretsmanager describe-secret --secret-id $SecretName) {
      $secretId = $SecretName
    }
  } else {
    $secretValues = [ordered]@{}
    foreach ($key in @(
      "LLM_API_KEY",
      "AMAP_WEB_KEY",
      "REPLICATE_API_TOKEN"
    )) {
      $value = Get-OptionalValue -Object $config -Name $key
      if ($value) {
        $secretValues[$key] = $value
      }
    }

    if ($secretValues.Count -gt 0) {
      $secretJson = $secretValues | ConvertTo-Json -Compress
      $secretFile = Join-Path ([System.IO.Path]::GetTempPath()) "$StackName-secret.json"
      Set-Content -LiteralPath $secretFile -Value $secretJson -NoNewline -Encoding UTF8
      try {
        $secretExists = Test-AwsCommand secretsmanager describe-secret --secret-id $SecretName

        if ($secretExists) {
          Write-Host "Updating Secrets Manager secret $SecretName."
          Invoke-Aws secretsmanager put-secret-value `
            --secret-id $SecretName `
            --secret-string "file://$secretFile" | Out-Null
        } else {
          Write-Host "Creating Secrets Manager secret $SecretName."
          Invoke-Aws secretsmanager create-secret `
            --name $SecretName `
            --secret-string "file://$secretFile" | Out-Null
        }
        $secretId = $SecretName
      } finally {
        Remove-Item -LiteralPath $secretFile -Force -ErrorAction SilentlyContinue
      }
    }
  }

  New-Item -ItemType Directory -Force -Path ".aws-sam" | Out-Null
  Invoke-Aws cloudformation package `
    --template-file template.yaml `
    --s3-bucket $ArtifactBucket `
    --output-template-file ".aws-sam\packaged.yaml" | Out-Null

  $parameterOverrides = @(
    "AwsRegion=$Region",
    "CognitoUserPoolId=$userPoolId",
    "CognitoAppClientId=$appClientId",
    "AllowedOrigins=*",
    "SecretId=$secretId",
    "LlmBaseUrl=$(Get-OptionalValue -Object $config -Name "LLM_BASE_URL" -Default "https://api.deepseek.com/v1")",
    "LlmModel=$(Get-OptionalValue -Object $config -Name "LLM_MODEL" -Default "deepseek-chat")"
  )

  Invoke-Aws cloudformation deploy `
    --template-file ".aws-sam\packaged.yaml" `
    --stack-name $StackName `
    --capabilities CAPABILITY_IAM `
    --parameter-overrides @parameterOverrides `
    --no-fail-on-empty-changeset | Out-Null

  $apiUrl = Invoke-Aws cloudformation describe-stacks `
    --stack-name $StackName `
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue | [0]" `
    --output text | Out-String
  $apiUrl = $apiUrl.Trim()

  Write-Host "Deployment complete."
  Write-Host "API URL: $apiUrl"
  Write-Host "Use scripts\test-proxy.ps1 with a Cognito ID token to run authenticated smoke tests."
} finally {
  Pop-Location
}
