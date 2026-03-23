# Memoria Audio Analysis API - Docker 部署指南

## 📋 概述

本项目已转换为Docker容器化部署，解决了原Lambda ZIP包大小超限问题。提供以下两种部署选项：

### 方案对比

| 功能 | Lambda + ECR | ECS/Fargate |
|------|-------------|-----------|
| 成本 | 低（按调用次数计费） | 中等（按运行时间计费） |
| 最大内存 | 10GB | 无限 |
| 冷启动 | 30-60秒 | 较少 |
| 最适用 | 低频、高峰值流量 | 24/7运行 |
| 复杂度 | 低 | 中等 |

---

## 🚀 快速开始

### 前置要求

- Docker Desktop 安装（Windows/Mac）或 Docker Engine（Linux）
- AWS CLI v2+
- AWS IAM用户凭证（需要ECR、Lambda、IAM权限）
- PowerShell 7+（Windows）或 Bash（Mac/Linux）

### 1️⃣ 本地测试

```bash
# 克隆/进入项目目录
cd ai_tools/audio_api

# 使用docker-compose测试（推荐）
docker-compose up -d

# 访问API文档
# Swagger UI: http://localhost:8000/docs
# ReDoc: http://localhost:8000/redoc

# 查看日志
docker-compose logs -f librosa-api

# 清理
docker-compose down
```

**测试API调用：**

```bash
# 上传音频文件进行分析
curl -X POST "http://localhost:8000/api/analyze_beats" \\
  -F "audio=@test_audio.mp3"

# 响应示例：
# {
#   "bpm": 128.5,
#   "data": [
#     {"ms": 0, "energy": 0.0234},
#     {"ms": 468, "energy": 0.0567}
#   ]
# }
```

---

## 🌐 Lambda 容器镜像部署

### 第一步：配置AWS

```powershell
# Windows PowerShell
$env:AWS_PROFILE = "default"
$env:AWS_REGION = "ap-northeast-2"

# 验证AWS配置
aws sts get-caller-identity --profile default
```

### 第二步：自动部署（推荐）

```powershell
# 使用部署脚本（一键部署）
.\\deploy.ps1 -Action all -AwsProfile default -AwsRegion ap-northeast-2
```

**脚本会自动执行：**
1. ✅ 构建Docker镜像
2. ✅ 本地测试（docker-compose）
3. ✅ 推送镜像到ECR
4. ✅ 通过SAM部署到Lambda

### 第三步：手动部署（分步骤）

```powershell
# 1. 构建镜像
docker build -t memoria-librosa-api:latest -f Dockerfile .

# 2. 获取AWS账户ID
$accountId = aws sts get-caller-identity --query Account --output text --profile default
$region = "ap-northeast-2"

# 3. 创建ECR仓库
aws ecr create-repository \\
  --repository-name memoria-librosa-api \\
  --region $region \\
  --profile default

# 4. 登录到ECR
aws ecr get-login-password --region $region --profile default | \\
  docker login --username AWS --password-stdin $accountId.dkr.ecr.$region.amazonaws.com

# 5. 标记并推送镜像
$imageUri = "$accountId.dkr.ecr.$region.amazonaws.com/memoria-librosa-api:latest"
docker tag memoria-librosa-api:latest $imageUri
docker push $imageUri

# 6. 部署到Lambda
sam deploy \\
  -t template-container.yaml \\
  --stack-name memoria-librosa-function \\
  --region $region \\
  --profile default \\
  --parameter-overrides ImageUri=$imageUri \\
  --capabilities CAPABILITY_IAM
```

### 部署输出

成功部署后，你将获得：

```
✅ CloudFormation Stack: memoria-librosa-function
📌 API Gateway URL: https://xxx.execute-api.ap-northeast-2.amazonaws.com
🔗 Lambda函数: memoria-librosa-function
📦 ECR仓库: memoria-librosa-api
🪣 S3存储桶: memoria-audio-storage-xxxxxx-ap-northeast-2
```

---

## 📊 Lambda 容器配置详解

### 资源限制

```yaml
MemorySize: 3008      # 最大内存（MB）- librosa需要足够的内存
Timeout: 900          # 超时时间（秒）- 15分钟用于处理大文件
EphemeralStorage: 10240  # 临时存储（MB）- 10GB用于临时文件
```

### 成本估算（按ap-northeast-2地区）

```
内存: 3008 MB
每次调用: ~$0.000017 (1秒计算时间)
每月调用1000次: ~$0.017
每月1小时总计算时间: ~$0.0167
```

---

## 🐳 ECS/Fargate 部署（可选）

适用于需要 24/7 运行的场景。

```powershell
# 部署到ECS
sam deploy \\
  -t ecs-template.yaml \\
  --stack-name memoria-audio-ecs \\
  --region ap-northeast-2 \\
  --profile default \\
  --capabilities CAPABILITY_IAM,CAPABILITY_NAMED_IAM
```

详见 [ecs-template.yaml](./ecs-template.yaml)

---

## 🔍 监控和调试

### CloudWatch日志

```bash
# 查看最新日志
aws logs tail /aws/lambda/memoria-librosa-function --follow --profile default

# 搜索错误
aws logs filter-log-events \\
  --log-group-name /aws/lambda/memoria-librosa-function \\
  --filter-pattern "ERROR" \\
  --profile default
```

### X-Ray追踪（可选）

编辑 `template-container.yaml` 添加：

```yaml
LibrosaFunction:
  Properties:
    TracingConfig:
      Mode: Active
```

---

## 🆘 常见问题

### Q1: 容器镜像超过Lambda限制？
**A:** Lambda容器镜像限制为10GB（解压）。如果超过：
- 删除不必要的依赖
- 使用多阶段构建优化镜像大小
- 考虑使用ECS/Fargate

### Q2: 冷启动太慢？
**A:** Lambda冷启动通常30-60秒。优化方法：
- 预热函数（定期调用keep-alive）
- 使用Provisioned Concurrency（需付费）
- 切换到ECS/Fargate

### Q3: 如何上传大文件？
**A:** Lambda请求体限制为6MB。大文件处理：
```python
# 使用S3预签名URL
s3_url = generate_presigned_url()  # 上传到S3
# Lambda从S3读取处理
audio_file = s3.get_object(Bucket, Key)
```

### Q4: 如何更新部署？
**A:**
```powershell
# 修改代码后重新构建和部署
.\\deploy.ps1 -Action deploy-lambda -ImageTag v1.0.1
```

---

## 📝 环境变量配置

在 `template-container.yaml` 中添加：

```yaml
LibrosaFunction:
  Properties:
    Environment:
      Variables:
        LOG_LEVEL: INFO
        MAX_FILE_SIZE: "52428800"  # 50MB
        CACHE_DIR: "/tmp/cache"
```

---

## 🔒 安全性建议

1. **IAM角色最小权限原则**
   ```yaml
   LambdaExecutionRole:
     ManagedPolicyArns:
       - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   ```

2. **ECR镜像扫描**
   ```yaml
   AudioApiRegistry:
     ImageScanningConfiguration:
       ScanOnPush: true
   ```

3. **API授权**
   ```yaml
   AudioAnalysisApi:
     Auth:
       ApiKeyRequired: true
   ```

---

## 📦 CI/CD 集成

### GitHub Actions示例

```yaml
name: Deploy to Lambda

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: \${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: \${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2
      - name: Build and Push
        run: |
          ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)
          docker build -t memoria-librosa-api:latest .
          docker tag memoria-librosa-api:latest \$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/memoria-librosa-api:latest
          docker push \$ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/memoria-librosa-api:latest
      - name: Deploy
        run: sam deploy -t template-container.yaml --no-confirm-changeset
```

---

## 🧹 清理资源

```powershell
# 删除CloudFormation栈
aws cloudformation delete-stack \\
  --stack-name memoria-librosa-function \\
  --region ap-northeast-2 \\
  --profile default

# 删除ECR仓库
aws ecr delete-repository \\
  --repository-name memoria-librosa-api \\
  --force \\
  --region ap-northeast-2 \\
  --profile default

# 使用脚本清理
.\\deploy.ps1 -Action clean
```

---

## 📚 相关文档

- [AWS SAM 文档](https://docs.aws.amazon.com/serverless-application-model/)
- [Lambda 容器镜像支持](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [Docker 官方文档](https://docs.docker.com/)
- [librosa 文档](https://librosa.org/)

---

**最后更新**: 2026-03-23  
**维护者**: Memoria Team
