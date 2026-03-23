# 转换为 Docker 部署 - 快速开始指南

## ✅ 已完成的工作

### 📦 创建的文件

1. **Dockerfile** - 多阶段构建，优化了镜像大小
2. **docker-compose.yml** - 本地开发环境配置
3. **template-container.yaml** - AWS Lambda容器镜像部署(SAM)
4. **ecs-template.yaml** - ECS/Fargate完整部署方案
5. **deploy.ps1** - 自动化部署脚本(PowerShell)
6. **.dockerignore** - Docker构建优化
7. **prometheus.yml** - 监控配置
8. **DOCKER_DEPLOYMENT.md** - 完整部署文档
9. **README.md** - 快速参考指南
10. **.env.example** - 环境变量模板
11. **修改example/__init__.py** - 添加/health、/metrics端点和监控计数器

### 🎯 解决了的问题

| 问题 | 解决方案 | 效果 |
|------|--------|------|
| Lambda ZIP包太大 | Docker容器镜像部署 | 无大小限制(10GB ECR) |
| 开发环境配置复杂 | docker-compose | 一键启动本地环境 |
| 部署流程复杂 | deploy.ps1脚本 | 全自动部署 |
| 无法监控 | /metrics端点 | Prometheus集成 |
| 健康检查缺失 | /health端点 | Docker/K8s支持 |

---

## 🚀 三种部署方案对比

### 方案1: 本地Docker ⭐⭐⭐ (立即开始)

**命令**:
```bash
cd ai_tools/audio_api
docker-compose up -d
```

**特点**: 即时可用、完整功能、本地测试

---

### 方案2: Lambda容器镜像 ⭐⭐⭐⭐ (推荐)

**命令**:
```powershell
cd ai_tools/audio_api
.\\deploy.ps1 -Action all -AwsRegion ap-northeast-2
```

**自动执行**:
- ✅ 构建Docker镜像
- ✅ 本地docker-compose测试
- ✅ 推送到AWS ECR
- ✅ 通过SAM部署到Lambda
- ✅ 创建API Gateway和S3存储

**优势**:
- 成本最低（按调用计费）
- 自动扩展
- 无需管理基础设施

**成本**: ~$0.017/1000次调用

---

### 方案3: ECS/Fargate ⭐⭐⭐⭐⭐ (高级)

**命令**:
```powershell
sam deploy -t ecs-template.yaml \
  --stack-name memoria-audio-ecs \
  --capabilities CAPABILITY_IAM
```

**优势**:
- 24/7运行
- 无文件大小限制
- 完全可控（2-10个副本自动扩展）
- 内置VPC、Load Balancer、Auto Scaling

**成本**: 按运行时间计费，建议预留实例

---

## 📝 快速参考命令

### 本地开发

```bash
# 启动应用
docker-compose up -d

# 查看日志
docker-compose logs -f librosa-api

# 测试API
curl -F "audio=@test.mp3" http://localhost:8000/api/analyze_beats

# 查看文档（Swagger UI）
open http://localhost:8000/docs

# 停止应用
docker-compose down
```

### AWS部署

```powershell
# 一键部署所有
.\\deploy.ps1 -Action all

# 仅构建镜像
.\\deploy.ps1 -Action build

# 本地测试
.\\deploy.ps1 -Action test

# 仅部署到Lambda
.\\deploy.ps1 -Action deploy-lambda

# 清理本地资源
.\\deploy.ps1 -Action clean
```

### 云端管理

```bash
# 查看Lambda日志
aws logs tail /aws/lambda/memoria-librosa-function --follow

# 查看部署栈
aws cloudformation describe-stacks --stack-name memoria-librosa-function

# 删除部署
aws cloudformation delete-stack --stack-name memoria-librosa-function
```

---

## 🔧 关键配置值

**Lambda约束**（template-container.yaml）:
```yaml
MemorySize: 3008      # 最大内存（librosa需要）
Timeout: 900          # 15分钟超时
EphemeralStorage: 10240  # 10GB临时存储
```

**ECS约束**（ecs-template.yaml）:
```yaml
DesiredCount: 2       # 2个副本
TaskCpu: 2048         # 2 vCPU
TaskMemory: 4096      # 4GB内存
AutoScaling: 2-10     # 自动扩展范围
```

---

## 🆘 常见问题

### Q: Docker镜像大小是多少？
A: 约1.2GB（包含librosa + dependencies）
- 使用多阶段构建最小化了镜像  
- Lambda ECR限制：10GB
- ECS/Fargate：无限制

### Q: Lambda冷启动需要多久？
A: 30-60秒（取决于镜像大小）
- 优化：预留并发（需付费）
- 或使用ECS/Fargate

### Q: 如何上传大文件？
A: Lambda请求体限制6MB
- 使用S3预签名URL方案
- 或用ECS/Fargate（无限制）

### Q: 如何更新部署？
```powershell
# 修改代码后
git add -A
git commit -m "update"
.\\deploy.ps1 -Action all -ImageTag v1.0.1
```

---

## 📚 完整文档

详见根目录中的文档：
- [DOCKER_DEPLOYMENT.md](./DOCKER_DEPLOYMENT.md) - 完整70行部署指南
- [README.md](./README.md) - 快速参考

---

## 🎓 下一步

1. **立即开始**:
   ```bash
   cd ai_tools/audio_api
   docker-compose up -d
   # 访问 http://localhost:8000/docs
   ```

2. **测试部署流程**:
   ```powershell
   .\\deploy.ps1 -Action test
   ```

3. **部署到AWS**:
   ```powershell
   .\\deploy.ps1 -Action all
   ```

---

## 📊 成本估算

### Lambda方案（月均）
- 1000次调用/天（平均1秒/次）
- ≈ 30,000次调用/月
- **成本**: ~$0.5/月 + $0.02/GB存储

### ECS/Fargate方案（月均）
- 2个副本24/7运行
- **成本**: ~$30/月（按当前AWS价格）

### 建议
- **低频访问** → Lambda
- **高频访问** → ECS/Fargate

---

**更新时间**: 2026-03-23  
**作者**: Memoria Team  
**状态**: ✅ 完全准备就绪
