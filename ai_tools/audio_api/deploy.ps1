#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Memoria Audio API - Docker部署脚本
  支持本地测试和AWS Lambda容器镜像部署

.DESCRIPTION
  此脚本支持以下功能：
  - 本地Docker构建和测试
  - 推送镜像到AWS ECR
  - 部署到AWS Lambda (使用容器镜像)
  - 部署到AWS ECS/Fargate (可选)

.PARAMETER Action
  执行的操作: build, test, deploy-lambda, deploy-ecs, all

.PARAMETER AwsProfile
  AWS CLI配置文件名称

.PARAMETER AwsRegion
  AWS地区代码

.EXAMPLE
  .\deploy.ps1 -Action build
  .\deploy.ps1 -Action all -AwsProfile default -AwsRegion ap-northeast-2
#>

param(
    [ValidateSet('build', 'test', 'deploy-lambda', 'deploy-ecs', 'all', 'clean')]
    [string]$Action = 'all',
    
    [string]$AwsProfile = 'default',
    [string]$AwsRegion = 'ap-northeast-2',
    [string]$StackName = 'memoria-librosa-function',
    [string]$ImageTag = 'latest'
)

$ErrorActionPreference = 'Stop'

# 配置
$RepositoryName = 'memoria-librosa-api'
$ImageName = 'memoria-librosa-api'
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = $ScriptPath

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Memoria Audio API 部署工具" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "操作: $Action" -ForegroundColor Yellow
Write-Host "AWS地区: $AwsRegion" -ForegroundColor Yellow
Write-Host "AWS Profile: $AwsProfile" -ForegroundColor Yellow

# =============================================================================
# 函数定义
# =============================================================================

function Get-AwsInfo {
    $env:AWS_PROFILE = $AwsProfile
    $env:AWS_REGION = $AwsRegion
    
    Write-Host "`n📋 获取AWS账户信息..." -ForegroundColor Blue
    $accountId = aws sts get-caller-identity --query Account --output text --profile $AwsProfile
    if (!$accountId) {
        throw "❌ 无法获取AWS账户ID。请检查AWS凭证。"
    }
    Write-Host "✅ AWS账户ID: $accountId"
    return $accountId
}

function Build-Image {
    Write-Host "`n🔨 构建Docker镜像..." -ForegroundColor Blue
    
    Push-Location $ProjectRoot
    try {
        $imagePath = "$($ImageName):$($ImageTag)"
        Write-Host "📦 镜像标签: $imagePath" -ForegroundColor Yellow
        
        docker build -t $imagePath -f Dockerfile . --progress=plain
        if ($LASTEXITCODE -ne 0) {
            throw "❌ Docker构建失败"
        }
        Write-Host "✅ Docker镜像构建成功"
        return $imagePath
    }
    finally {
        Pop-Location
    }
}

function Test-Image {
    Write-Host "`n🧪 测试Docker容器..." -ForegroundColor Blue
    
    Write-Host "🚀 启动docker-compose..." -ForegroundColor Yellow
    docker-compose -f "$ProjectRoot/docker-compose.yml" up -d
    
    Start-Sleep -Seconds 10
    
    Write-Host "📡 测试API端点..." -ForegroundColor Yellow
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/docs" -TimeoutSec 5 -ErrorAction Stop
        Write-Host "✅ API健康检查通过"
    }
    catch {
        Write-Host "⚠️ 警告: API可能未完全启动，但继续进行..."
    }
}

function Push-ToEcr {
    param(
        [string]$AccountId,
        [string]$ImagePath
    )
    
    Write-Host "`n📤 推送镜像到ECR..." -ForegroundColor Blue
    
    $ecrUri = "$AccountId.dkr.ecr.$AwsRegion.amazonaws.com"
    $ecrRepo = "$ecrUri/$RepositoryName"
    
    # 创建ECR仓库（如果不存在）
    Write-Host "🏗️  检查ECR仓库..." -ForegroundColor Yellow
    $repoExists = aws ecr describe-repositories --repository-names $RepositoryName `
        --region $AwsRegion --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "📝 创建ECR仓库: $RepositoryName" -ForegroundColor Yellow
        aws ecr create-repository `
            --repository-name $RepositoryName `
            --region $AwsRegion `
            --profile $AwsProfile `
            --image-scanning-configuration scanOnPush=false `
            --encryption-configuration encryptionType=AES256
    }
    
    # ECR登录
    Write-Host "🔐 登录到ECR..." -ForegroundColor Yellow
    $loginCmd = aws ecr get-login-password --region $AwsRegion --profile $AwsProfile | `
        docker login --username AWS --password-stdin $ecrUri
    
    if ($LASTEXITCODE -ne 0) {
        throw "❌ ECR登录失败"
    }
    
    # 标记镜像
    $targetImage = "$ecrRepo`:$ImageTag"
    Write-Host "🏷️  标记镜像: $targetImage" -ForegroundColor Yellow
    docker tag $ImagePath $targetImage
    
    # 推送镜像
    Write-Host "🚀 推送镜像到ECR..." -ForegroundColor Yellow
    docker push $targetImage
    
    if ($LASTEXITCODE -ne 0) {
        throw "❌ 推送镜像失败"
    }
    
    Write-Host "✅ 镜像推送成功: $targetImage"
    return $targetImage
}

function Deploy-ToLambda {
    param(
        [string]$ImageUri
    )
    
    Write-Host "`n⚡ 部署到AWS Lambda..." -ForegroundColor Blue
    
    # 构建SAM配置
    $samConfig = @"
version = 0.1

[default]
[default.deploy]
region = "$AwsRegion"
stack_name = "$StackName"
confirm_changeset = false
capabilities = "CAPABILITY_IAM"

[default.deploy.parameters]
stack_name = "$StackName"
s3_prefix = "$StackName"
region = "$AwsRegion"
image_repositories = ["LibrosaFunction=$ImageUri"]
"@

    Write-Host "📝 创建samconfig-container.toml..." -ForegroundColor Yellow
    $samConfigPath = Join-Path $ProjectRoot "samconfig-container.toml"
    $samConfig | Out-File -FilePath $samConfigPath -Encoding UTF8
    
    # SAM部署
    Write-Host "🚀 执行SAM部署..." -ForegroundColor Yellow
    sam deploy `
        -t template-container.yaml `
        --config-file $samConfigPath `
        --profile $AwsProfile `
        --region $AwsRegion
    
    if ($LASTEXITCODE -ne 0) {
        throw "❌ SAM部署失败"
    }
    
    Write-Host "✅ Lambda部署成功"
    
    # 获取API端点
    Write-Host "`n📌 获取API端点..." -ForegroundColor Yellow
    $stack = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --region $AwsRegion `
        --profile $AwsProfile `
        --query 'Stacks[0].Outputs' `
        --output json | ConvertFrom-Json
    
    foreach ($output in $stack) {
        if ($output.OutputKey -eq "ApiEndpoint") {
            Write-Host "🔗 API端点: $($output.OutputValue)" -ForegroundColor Green
        }
    }
}

function Deploy-ToEcs {
    Write-Host "`n🐳 部署到ECS/Fargate..." -ForegroundColor Blue
    Write-Host "📄 查看ecs-template.yaml了解ECS部署详情" -ForegroundColor Yellow
    Write-Host "命令: sam deploy -t ecs-template.yaml --profile $AwsProfile --region $AwsRegion" -ForegroundColor Yellow
}

function Cleanup {
    Write-Host "`n🧹 清理本地资源..." -ForegroundColor Blue
    
    Write-Host "停止docker-compose..." -ForegroundColor Yellow
    docker-compose -f "$ProjectRoot/docker-compose.yml" down --volumes
    
    Write-Host "删除本地镜像..." -ForegroundColor Yellow
    docker rmi "$($ImageName):$($ImageTag)" -f 2>&1 | Out-Null
    
    Write-Host "✅ 清理完成"
}

# =============================================================================
# 主执行流程
# =============================================================================

try {
    $accountId = Get-AwsInfo
    
    if ($Action -eq 'clean') {
        Cleanup
        exit 0
    }
    
    if ($Action -in @('build', 'all', 'test')) {
        $imagePath = Build-Image
    }
    
    if ($Action -in @('test', 'all')) {
        Test-Image
    }
    
    if ($Action -in @('deploy-lambda', 'all')) {
        if (!$imagePath) {
            $imagePath = Build-Image
        }
        $imageUri = Push-ToEcr -AccountId $accountId -ImagePath $imagePath
        Deploy-ToLambda -ImageUri $imageUri
    }
    
    if ($Action -eq 'deploy-ecs') {
        Deploy-ToEcs
    }
    
    Write-Host "`n✅ 所有操作完成" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ 错误: $_" -ForegroundColor Red
    exit 1
}
