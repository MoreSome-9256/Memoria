# Memoria Audio API - 快速参考

## 📦 文件说明

| 文件 | 用途 |
|------|------|
| `Dockerfile` | Docker镜像构建配置 |
| `docker-compose.yml` | 本地开发环境 |
| `template-container.yaml` | Lambda容器镜像部署 (SAM) |
| `ecs-template.yaml` | ECS/Fargate完整部署 (SAM) |
| `deploy.ps1` | 自动化部署脚本 |
| `DOCKER_DEPLOYMENT.md` | 完整部署指南 |
| `.env.example` | 环境变量模板 |

## 🚀 三种部署方式

### 方式1️⃣: 本地Docker开发 ⭐ 最快上手

```bash
cd audio_api
docker-compose up -d
# API: http://localhost:8000/docs
# 日志: docker-compose logs -f librosa-api
# 清理: docker-compose down
```

### 方式2️⃣: Lambda容器镜像 ⭐ 推荐生产环境

**优点**: 成本低、自动扩展、无需管理基础设施  
**缺点**: 冷启动30-60秒、请求体限制6MB

```powershell
# 一键部署
.\\deploy.ps1 -Action all -AwsRegion ap-northeast-2

# 获取API端点
aws cloudformation describe-stacks \\
  --stack-name memoria-librosa-function \\
  --query 'Stacks[0].Outputs' \\
  --region ap-northeast-2
```

### 方式3️⃣: ECS/Fargate ⭐ 高级需求

**优点**: 24/7运行、无文件大小限制、完全可控  
**缺点**: 成本较高、管理复杂度高

```powershell
sam deploy \\
  -t ecs-template.yaml \\
  --stack-name memoria-audio-ecs \\
  --capabilities CAPABILITY_IAM
```

---

## 🐛 常见命令

### 本地测试
```bash
# 上传音频文件测试
curl -X POST "http://localhost:8000/api/analyze_beats" \\
  -F "audio=@sample.mp3"

# 查看API文档
open http://localhost:8000/docs
```

### 云端操作
```bash
# 查看Lambda日志
aws logs tail /aws/lambda/memoria-librosa-function --follow

# 测试Lambda函数
aws lambda invoke \\
  --function-name memoria-librosa-function \\
  response.json

# 查看部署详情
aws cloudformation describe-stacks --stack-name memoria-librosa-function
```

### 镜像管理
```bash
# 查看本地镜像
docker images | grep memoria

# 查看ECR镜像
aws ecr describe-images --repository-name memoria-librosa-api

# 删除镜像
docker rmi memoria-librosa-api:latest
aws ecr batch-delete-image --repository-name memoria-librosa-api --image-ids imageTag=latest
```

---

## 📊 性能优化建议

| 优化项 | 方法 | 效果 |
|--------|------|------|
| 冷启动 | Lambda Provisioned Concurrency | -50% 时间 |
| 内存占用 | 精简base image | -20% 大小 |
| 并发处理 | 使用异步任务队列 (SQS+Lambda) | +3倍吞吐 |
| 成本 | 利用定时任务预热 | -30% 成本 |

---

## 🔐 安全清单

- [ ] Enable S3 encryption
- [ ] Set up IAM roles with least privilege
- [ ] Enable CloudTrail for audit
- [ ] Configure VPC endpoints (for ECS)
- [ ] Set up WAF rules (if public API)
- [ ] Enable API authentication/API Keys
- [ ] Regular security scanning of ECR images

---

## 📞 快速支持

**问题**: Docker构建失败  
**解决**: `docker build --progress=plain --no-cache .`

**问题**: Lambda超时  
**解决**: 增加 `Timeout: 900` 在SAM配置中

**问题**: 镜像过大  
**解决**: 查看 [Dockerfile优化技巧](#dockerfile-优化)

---

## 📚 相关资源

- [完整文档](./DOCKER_DEPLOYMENT.md)
- [AWS SAM 快速开始](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [Lambda 容器支持](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [ECS Fargate 指南](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html)

---

**最后更新**: 2026-03-23
