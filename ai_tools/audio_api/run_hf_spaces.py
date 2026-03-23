#!/usr/bin/env python3
"""
HuggingFace Spaces 启动脚本
用于部署带有 Cognito 鉴权的 FastAPI 服务
"""

import os
import sys
import logging
from pathlib import Path

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def check_environment():
    """检查必须的环境变量"""
    required_vars = [
        'AWS_REGION',
        'COGNITO_USER_POOL_ID',
    ]
    
    missing_vars = []
    for var in required_vars:
        if not os.getenv(var):
            missing_vars.append(var)
    
    if missing_vars:
        logger.error(f"❌ 缺少必须的环境变量: {', '.join(missing_vars)}")
        logger.error("请在 HuggingFace Space Settings → Secrets 中添加这些变量")
        return False
    
    logger.info("✅ 环境变量检查通过")
    return True


def check_dependencies():
    """检查必须的依赖库"""
    required_packages = [
        'fastapi',
        'librosa',
        'uvicorn',
        'jwt',
        'jose',
    ]
    
    missing_packages = []
    for package in required_packages:
        try:
            __import__(package)
        except ImportError:
            missing_packages.append(package)
    
    if missing_packages:
        logger.error(f"❌ 缺少必须的依赖: {', '.join(missing_packages)}")
        logger.error("运行: pip install -r requirements.txt")
        return False
    
    logger.info("✅ 依赖库检查通过")
    return True


def verify_cognito_connection():
    """验证能否连接到 Cognito"""
    try:
        import requests
        
        region = os.getenv('AWS_REGION', 'ap-southeast-1')
        user_pool_id = os.getenv('COGNITO_USER_POOL_ID', '')
        
        if not user_pool_id:
            logger.warning("⚠️  COGNITO_USER_POOL_ID 未设置，跳过连接验证")
            return True
        
        jwks_url = f"https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json"
        
        logger.info(f"🔐 尝试连接到 Cognito JWKS: {jwks_url[:50]}...")
        response = requests.get(jwks_url, timeout=5)
        
        if response.status_code == 200:
            logger.info("✅ Cognito 连接验证通过")
            return True
        else:
            logger.warning(f"⚠️  Cognito 返回状态码 {response.status_code}")
            return True  # 不中断启动
            
    except Exception as e:
        logger.warning(f"⚠️  无法验证 Cognito 连接: {e}")
        logger.warning("若在启动后仍无法连接，请检查网络和环境变量")
        return True  # 不中断启动


def main():
    """主启动函数"""
    logger.info("=" * 60)
    logger.info("🚀 HuggingFace Spaces - Memoria Audio API Starting")
    logger.info("=" * 60)
    
    # 1. 环境检查
    if not check_environment():
        sys.exit(1)
    
    # 2. 依赖检查
    if not check_dependencies():
        sys.exit(2)
    
    # 3. Cognito 连接验证
    verify_cognito_connection()
    
    logger.info("")
    logger.info("✅ 所有预检查通过！启动 FastAPI 服务...")
    logger.info("")


if __name__ == "__main__":
    main()
