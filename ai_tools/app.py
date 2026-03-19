import librosa
import numpy as np
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import tempfile
import os

app = FastAPI()

@app.post("/api/analyze_beats")
async def analyze_beats(audio: UploadFile = File(...)):
    print(f"🎵 收到音频文件: {audio.filename}")
    
    # 🌟 1. 动态提取真实的后缀名 (比如 .m4a, .wav)
    ext = os.path.splitext(audio.filename)[1]
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

# 启动命令: uvicorn app:app --host 0.0.0.0 --port 8000