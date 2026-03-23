import librosa
import numpy as np
from fastapi import FastAPI, UploadFile, File, HTTPException, status, Security, Query
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import tempfile
import os
import time
import base64
from typing import Optional, Any, Dict
import requests
from jose import jwt, JWTError
import logging
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

# 🔐 日志配置
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _env_bool(name: str, default: bool) -> bool:
    val = os.getenv(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}


ENABLE_DOCS = _env_bool("AUDIO_API_ENABLE_DOCS", False)

app = FastAPI(
    docs_url="/docs" if ENABLE_DOCS else None,
    redoc_url="/redoc" if ENABLE_DOCS else None,
    openapi_url="/openapi.json" if ENABLE_DOCS else None,
)

bearer_scheme = HTTPBearer(auto_error=False)

# 🔐 CORS 配置：默认关闭跨域，仅在配置了来源时启用。
allowed_origins_raw = os.getenv("AUDIO_API_ALLOWED_ORIGINS", "")
allowed_origins = [x.strip() for x in allowed_origins_raw.split(",") if x.strip()]
if allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=False,
        allow_methods=["POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )

# 🔐 从环境变量或配置文件读取 Cognito 配置
COGNITO_REGION = os.getenv("AWS_REGION", "ap-southeast-2")
COGNITO_USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID", "")
COGNITO_APP_CLIENT_ID = os.getenv("COGNITO_APP_CLIENT_ID", "")
COGNITO_DOMAIN = f"cognito-idp.{COGNITO_REGION}.amazonaws.com"
COGNITO_ISSUER = f"https://{COGNITO_DOMAIN}/{COGNITO_USER_POOL_ID}"

# 🔐 Cognito JWKS 端点（用于验证 JWT 签名）
COGNITO_JWKS_URL = f"https://{COGNITO_DOMAIN}/{COGNITO_USER_POOL_ID}/.well-known/jwks.json"

# 🔐 缓存 JWKS（避免频繁请求）
_jwks_cache = None
_jwks_cache_time = None
JWKS_CACHE_TTL = 3600  # 1小时


async def get_jwks():
    """获取 Cognito JWKS 用于验证 JWT"""
    global _jwks_cache, _jwks_cache_time

    now = time.time()
    # 如果缓存有效，直接返回
    if _jwks_cache and _jwks_cache_time and (now - _jwks_cache_time) < JWKS_CACHE_TTL:
        return _jwks_cache
    
    try:
        response = requests.get(COGNITO_JWKS_URL, timeout=5)
        response.raise_for_status()
        _jwks_cache = response.json()
        _jwks_cache_time = now
        return _jwks_cache
    except Exception as e:
        logger.error(f"❌ 无法获取 Cognito JWKS: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="鉴权服务暂时不可用"
        )


def _b64url_to_int(value: str) -> int:
    padded = value + "=" * (-len(value) % 4)
    return int.from_bytes(base64.urlsafe_b64decode(padded), "big")


def build_public_key_pem(jwk_key: Dict[str, Any]) -> bytes:
    """将 JWKS 的 RSA key 转换成 PEM 公钥。"""
    n = _b64url_to_int(jwk_key["n"])
    e = _b64url_to_int(jwk_key["e"])
    public_numbers = rsa.RSAPublicNumbers(e, n)
    public_key_obj = public_numbers.public_key()
    return public_key_obj.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )


async def get_public_key_pem_from_token(token: str) -> bytes:
    """从 Cognito JWKS 获取对应的公钥用于验证 JWT。"""
    try:
        # 解码 JWT header 获取 kid（密钥 ID）
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        if not kid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="无效的 Token"
            )

        jwks = await get_jwks()

        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                return build_public_key_pem(key)

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="无法找到有效的签名密钥"
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="无效的 Token 格式"
        )


async def verify_cognito_token(token: str) -> dict:
    """验证 Cognito JWT Token（只接受 Access Token）。"""
    if not COGNITO_USER_POOL_ID:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="服务端未配置 COGNITO_USER_POOL_ID",
        )

    if not COGNITO_APP_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="服务端未配置 COGNITO_APP_CLIENT_ID",
        )

    try:
        pem = await get_public_key_pem_from_token(token)

        decoded = jwt.decode(
            token,
            pem,
            algorithms=["RS256"],
            options={"verify_aud": False},
            issuer=COGNITO_ISSUER,
        )

        token_use = decoded.get("token_use")
        if token_use != "access":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="仅允许 access token",
            )

        client_id = decoded.get("client_id")
        if client_id != COGNITO_APP_CLIENT_ID:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="token client_id 不匹配",
            )

        logger.info(f"✅ Token 验证通过，sub: {decoded.get('sub')}")
        return decoded

    except HTTPException:
        raise
    except JWTError as e:
        logger.warning(f"❌ Token 验证失败: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token 无效或已过期"
        )
    except Exception as e:
        logger.error(f"❌ Token 验证过程发生错误: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token 验证失败"
        )


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Security(bearer_scheme),
) -> dict:
    """只从 Authorization: Bearer <token> 读取鉴权。"""
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="缺少或无效的 Authorization Bearer Token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return await verify_cognito_token(credentials.credentials)

@app.post("/api/analyze_beats")
async def analyze_beats(
    audio: UploadFile = File(...),
    user_info: dict = Security(get_current_user),
    authorization: Optional[str] = Query(default=None),
):
    """分析音频节拍（需要 Cognito JWT 鉴权）"""

    # 不再允许通过 query 参数传 token，避免日志/代理泄漏。
    if authorization is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="禁止通过 query 参数传递 authorization，请使用 Authorization Bearer 头",
        )

    filename = audio.filename or ""
    print(f"🎵 收到音频文件: {filename or 'unknown'} (用户: {user_info.get('username')})")
    
    # 🌟 1. 动态提取真实的后缀名 (比如 .m4a, .wav)
    ext = os.path.splitext(filename)[1]
    # 兜底：如果有些手机没传后缀，默认给 mp3
    if not ext:
        ext = ".mp3"
        
    # 🌟 2. 存临时文件时，必须带着真实的后缀名
    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as temp_audio:
        content = await audio.read()
        temp_path = temp_audio.name
        temp_audio.write(content)
        
    # 🌟 3. 防护网：检查文件是不是空的
    file_size = len(content)
    print(f"📦 收到文件大小: {file_size} 字节")
    if file_size < 1024:
        os.remove(temp_path)
        return JSONResponse(content={"error": "文件为空或已损坏"}, status_code=400)

    try:
        # 2. Librosa 登场：加载音频
        # sr=22050 是 librosa 默认采样率，足够算节拍了，设低点跑得快
        y, sr = librosa.load(temp_path, sr=22050)

        # 3. 提取 BPM 和 节拍帧
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
        
        # 4. 把帧转换成具体的毫秒时间戳
        beat_times = librosa.frames_to_time(beat_frames, sr=sr)
        beat_ms = (beat_times * 1000).astype(int)

        # 5. 计算能量 (RMS) - 这步很关键，用来做画面的“震动”或“闪烁”特效
        rms = librosa.feature.rms(y=y)[0]
        rms_frames = librosa.frames_to_time(np.arange(len(rms)), sr=sr)

        # 6. 打包成 Flutter 需要的 JSON 格式
        results = []
        for i, ms in enumerate(beat_ms):
            # 找到离当前节拍最近的能量值
            idx = np.argmin(np.abs(rms_frames - beat_times[i]))
            energy = float(rms[idx])
            results.append({
                "ms": int(ms),
                "energy": round(energy, 4)
            })
            

        print(f"✅ 分析完成! BPM: {tempo[0]:.2f}, 节拍数: {len(results)}")
        
        return JSONResponse(content={
            "bpm": float(tempo[0]),
            "data": results
        })

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        # 扫地僧：用完记得把临时文件删了
        if os.path.exists(temp_path):
            os.remove(temp_path)

# handler = Mangum(app)

# if __name__ == "__main__":
#     import uvicorn
#     uvicorn.run(app, host="0.0.0.0", port=8000)
# 启动命令: 
# 1. 设置环境变量：
#    export AWS_REGION=ap-southeast-1
#    export COGNITO_USER_POOL_ID=ap-southeast-1_XXXXXXXXX
# 2. 启动服务：uvicorn app:app --host 0.0.0.0 --port 8000