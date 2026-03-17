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
    
    # 1. 把上传的二进制流存成临时文件
    with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_audio:
        content = await audio.read()
        temp_audio.write(content)
        temp_path = temp_audio.name

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