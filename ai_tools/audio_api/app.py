import librosa
import numpy as np
from fastapi import FastAPI, UploadFile, File, HTTPException, status, Security, Header, Cookie, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import tempfile
import os
import time
import base64
import uuid
from typing import Optional, Any, Dict
import requests
from jose import jwt, JWTError
import logging
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient

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


@app.middleware("http")
async def request_trace_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request.state.request_id = request_id
    started = time.time()
    client_host = request.client.host if request.client else "unknown"

    logger.info(
        "[REQ_START] id=%s method=%s path=%s query=%s client=%s ua=%s",
        request_id,
        request.method,
        request.url.path,
        request.url.query,
        client_host,
        request.headers.get("user-agent", ""),
    )

    try:
        response = await call_next(request)
    except Exception:
        cost_ms = int((time.time() - started) * 1000)
        logger.exception(
            "[REQ_CRASH] id=%s method=%s path=%s cost_ms=%s",
            request_id,
            request.method,
            request.url.path,
            cost_ms,
        )
        raise

    cost_ms = int((time.time() - started) * 1000)
    response.headers["X-Request-ID"] = request_id
    logger.info(
        "[REQ_END] id=%s method=%s path=%s status=%s cost_ms=%s",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        cost_ms,
    )
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    request_id = getattr(request.state, "request_id", "unknown")
    logger.warning(
        "[HTTP_ERROR] id=%s status=%s path=%s detail=%s",
        request_id,
        exc.status_code,
        request.url.path,
        exc.detail,
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "request_id": request_id},
        headers=exc.headers,
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    request_id = getattr(request.state, "request_id", "unknown")
    logger.exception(
        "[UNHANDLED_ERROR] id=%s path=%s msg=%s",
        request_id,
        request.url.path,
        str(exc),
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "服务器内部错误", "request_id": request_id},
    )

MEMORIA_TOKEN_HEADER = "X-Memoria-Token"
MEMORIA_TOKEN_COOKIE = "memoria_token"

# 🔐 CORS 配置：默认关闭跨域，仅在配置了来源时启用。
allowed_origins_raw = os.getenv("AUDIO_API_ALLOWED_ORIGINS", "")
allowed_origins = [x.strip() for x in allowed_origins_raw.split(",") if x.strip()]
if allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=False,
        allow_methods=["POST", "OPTIONS"],
        allow_headers=[MEMORIA_TOKEN_HEADER, "Content-Type"],
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
        logger.info("[JWKS_FETCH] url=%s", COGNITO_JWKS_URL)
        response = requests.get(COGNITO_JWKS_URL, timeout=5)
        response.raise_for_status()
        _jwks_cache = response.json()
        _jwks_cache_time = now
        logger.info("[JWKS_FETCH_OK] keys=%s", len(_jwks_cache.get("keys", [])))
        return _jwks_cache
    except Exception as e:
        logger.exception("❌ 无法获取 Cognito JWKS: %s", e)
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
    except Exception as e:
        logger.exception("❌ 从 Token 提取公钥失败: %s", e)
        raise


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
            logger.warning("❌ token_use 非 access: token_use=%s", token_use)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="仅允许 access token",
            )

        client_id = decoded.get("client_id")
        if client_id != COGNITO_APP_CLIENT_ID:
            logger.warning("❌ token client_id 不匹配: got=%s", client_id)
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
    x_memoria_token: Optional[str] = Header(default=None, alias=MEMORIA_TOKEN_HEADER),
    memoria_token: Optional[str] = Cookie(default=None, alias=MEMORIA_TOKEN_COOKIE),
) -> dict:
    """优先从自定义 Header 读取鉴权，Cookie 作为兜底。"""
    token = (x_memoria_token or "").strip() or (memoria_token or "").strip()
    logger.info(
        "[AUTH_INPUT] header_present=%s cookie_present=%s token_len=%s",
        bool(x_memoria_token),
        bool(memoria_token),
        len(token),
    )
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"缺少鉴权凭证，请通过 {MEMORIA_TOKEN_HEADER} header 或 {MEMORIA_TOKEN_COOKIE} cookie 传入 token",
        )
    return await verify_cognito_token(token)


@app.post("/chat/completions")  # to use the same auth dependency for both endpoints, this used for routing Deepseek's chat completions, 
async def ask_deepseek(
    request: Request,
    user_info: dict = Security(get_current_user),
):
    """Deepseek 的聊天接口（需要 Cognito JWT 鉴权）"""
    deepseek_api_key = os.getenv("DEEPSEEK_API_KEY", "")
    deepseek_api_url = os.getenv("DEEPSEEK_API_URL", "https://api.deepseek.com/v1/chat/completions")
    if not deepseek_api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="服务端未配置 DEEPSEEK_API_KEY",
        )
    
    # 此处直接转发请求 body 到 Deepseek API，使用 Deepseek 的 API Key 鉴权，完全异步、透明，不要有任何响应的差别
    try:

        httpx_aclient = AsyncClient(timeout=600)  # 全局复用的 Async HTTP Client，超时设置为 10 分钟，给 AI 充足的时间来处理复杂请求

        body = await request.body()
        headers = {
            "Authorization": f"Bearer {deepseek_api_key}",
            "Content-Type": "application/json"
        }
        # Call Deepseek API here
        logger.info(f"🚀 转发请求到 Deepseek API: url={deepseek_api_url} user={user_info.get('username')}")
        response = await httpx_aclient.post(deepseek_api_url, headers=headers, content=body)
        return response.read()
    except Exception as e:
        logger.error(f"❌ 调用 Deepseek API 失败: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="调用 Deepseek API 失败"
        )
    finally:
        await httpx_aclient.aclose()


@app.post("/api/analyze_beats")
async def analyze_beats(
    request: Request,
    audio: UploadFile = File(...),
    user_info: dict = Security(get_current_user),
):
    """分析音频节拍（需要 Cognito JWT 鉴权）"""

    request_id = getattr(request.state, "request_id", "unknown")

    filename = audio.filename or ""
    logger.info(
        "🎵 收到音频文件: request_id=%s filename=%s user=%s",
        request_id,
        filename or "unknown",
        user_info.get("username"),
    )
    
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
    logger.info("📦 收到文件大小: request_id=%s size=%s", request_id, file_size)
    if file_size < 512:
        os.remove(temp_path)
        return JSONResponse(
            content={"error": "文件为空或已损坏", "request_id": request_id},
            status_code=400,
        )

    try:
        started = time.time()
        # 2. Librosa 登场：加载音频
        # sr=22050 是 librosa 默认采样率，足够算节拍了，设低点跑得快
        y, sr = librosa.load(temp_path, sr=22050)
        logger.info(
            "[AUDIO_LOAD_OK] request_id=%s sr=%s samples=%s cost_ms=%s",
            request_id,
            sr,
            len(y),
            int((time.time() - started) * 1000),
        )

        # 3. 提取 BPM 和 节拍帧
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
        tempo_value = float(tempo[0]) if isinstance(tempo, np.ndarray) else float(tempo)
        logger.info(
            "[BEAT_TRACK_OK] request_id=%s beat_frames=%s tempo=%s",
            request_id,
            len(beat_frames),
            tempo_value,
        )
        
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
            

        logger.info(
            "✅ 分析完成! request_id=%s bpm=%s beats=%s",
            request_id,
            tempo_value,
            len(results),
        )
        
        return JSONResponse(content={
            "bpm": tempo_value,
            "data": results,
            "request_id": request_id,
        })

    except Exception as e:
        logger.exception("❌ 音频分析失败 request_id=%s err=%s", request_id, e)
        return JSONResponse(
            content={"error": str(e), "request_id": request_id},
            status_code=500,
        )
    finally:
        # 扫地僧：用完记得把临时文件删了
        if os.path.exists(temp_path):
            os.remove(temp_path)
            logger.info("🧹 已删除临时文件 request_id=%s path=%s", request_id, temp_path)

# handler = Mangum(app)

# if __name__ == "__main__":
#     import uvicorn
#     uvicorn.run(app, host="0.0.0.0", port=8000)
# 启动命令:
# 1. 设置环境变量：
#    export AWS_REGION=ap-southeast-1
#    export COGNITO_USER_POOL_ID=ap-southeast-1_XXXXXXXXX
# 2. 启动服务：uvicorn app:app --host 0.0.0.0 --port 8000
