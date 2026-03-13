import librosa
import json
import os
import numpy as np # 🌟 核心修复1：引爆全场的 Numpy 终于来了

def export_advanced_beats(audio_path, output_json):
    print(f"🎵 正在分析音频并提取能量值: {audio_path}")
    y, sr = librosa.load(audio_path)
    
    # 1. 提取节拍
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
    beat_times = librosa.frames_to_time(beats, sr=sr)
    
    # 2. 提取能量（RMS）
    # 每 2048 帧算一个能量均值
    rms = librosa.feature.rms(y=y)[0]
    rms_times = librosa.frames_to_time(range(len(rms)), sr=sr)
    
    # 3. 计算每个节拍点当时的能量强度
    beat_data = []
    for t in beat_times:
        # 找到最接近该节拍时间的能量索引
        idx = (np.abs(rms_times - t)).argmin()
        beat_data.append({
            "ms": int(t * 1000),
            "energy": float(rms[idx])
        })
    
    # 🌟 核心修复2：把 tempo 转成标准 Python float，防止 json.dump 不认识 Numpy 的 float32
    bpm_value = float(np.squeeze(tempo))

    # 导出包含能量信息的 JSON
    with open(output_json, 'w', encoding='utf-8') as f:
        json.dump({"bpm": bpm_value, "data": beat_data}, f, indent=4)
        
    # 🌟 核心修复3：把之前遗留的 beat_ms 改成了 beat_data
    print(f"✅ 导出成功！检测到 {len(beat_data)} 个节拍，BPM 为 {bpm_value:.2f}")
    print(f"📂 结果保存至: {output_json}")

# 使用示例
export_advanced_beats('assets/audio/sandal_leap.mp3', 'assets/audio/sandal_leap_beats.json')