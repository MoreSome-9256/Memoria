import os
import json
import time
import requests
import torch
import mobileclip
import jieba.posseg as pseg

# ================= 🌟 核心配置区 =================
# 从系统环境变量里读取，不要写死在代码里
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")

if not DEEPSEEK_API_KEY:
    print("❌ 错误：请先在终端设置环境变量 DEEPSEEK_API_KEY")
TXT_FILE = "ai_tools/现代汉语常用词表.txt"
OUTPUT_DICT_FILE = "ai_tools/ds_filtered_dict.json"      # 🌟 新增：保存 DS 中间翻译词表的路径
OUTPUT_VECTOR_FILE = "ai_tools/expanded_tags_vectors.json"
MAX_WORDS = 1000  # 我们这次多读一点，因为 DS 会大浪淘沙过滤掉很多废词！
# =================================================

def extract_visual_nouns(txt_path, max_count):
    """阶段一：利用 NLP 词性分析，从脏数据中初筛名词"""
    print("🧹 [阶段 1/3] 正在从校对版词表中清洗名词...")
    valid_flags = {'n', 'ns', 'nz', 's'}
    extracted_words = []

    with open(txt_path, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split()
            if not parts: continue
            word = parts[0].strip()

            if len(word) < 2 or len(word) > 5:
                continue

            words_pos = list(pseg.cut(word))
            if len(words_pos) == 1:
                w, flag = words_pos[0]
                if flag in valid_flags:
                    extracted_words.append(word)

            if len(extracted_words) >= max_count:
                break

    print(f"✅ 初筛完毕！提取了 {len(extracted_words)} 个名词交由 AI 裁判甄别。")
    return extracted_words

def batch_translate(words, batch_size=75):
    """阶段二：呼叫 DeepSeek 进行视觉过滤与翻译（引入分批处理机制）"""
    import time # 确保顶部引入了 time 模块

    total_batches = (len(words) + batch_size - 1) // batch_size
    print(f"🌐 [阶段 2/3] 准备将 {len(words)} 个词分成 {total_batches} 批发送给 AI (每批 {batch_size} 个)...")

    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json"
    }

    final_dict = {}

    # 将长长的单词列表切分成多个小块 (Chunks)
    for i in range(0, len(words), batch_size):
        batch = words[i:i + batch_size]
        batch_num = i // batch_size + 1
        print(f"   ⏳ 正在处理第 {batch_num}/{total_batches} 批 (本批 {len(batch)} 个词)...")

        payload = {
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": """你是一个严格的计算机视觉图像标签筛选与翻译专家。
用户会给你输入一组中文名词。请严格执行以下任务：
1. 彻底剔除所有抽象概念、宏观词汇和无法用相机直接拍出清晰主体的词（例如：中国、问题、社会、时间、思想、国家、历史等，直接删除）。
2. 仅保留人类日常手机相册中真实可见的具象物体、具体场景、食物、动植物或具体活动（例如：石拱桥、石膏、水杯、海滩等）。
3. 将保留下来的词汇精准翻译为英文单数名词（MobileCLIP提示词格式）。
仅返回纯JSON字典格式，键为保留的中文词，值为英文。不要输出任何其他废话。"""},
                {"role": "user", "content": json.dumps(batch, ensure_ascii=False)}
            ],
            "response_format": {"type": "json_object"}
        }

        try:
            response = requests.post(url, headers=headers, json=payload)
            response.raise_for_status()
            content = response.json()['choices'][0]['message']['content']

            # 解析本批次的 JSON 并合并到总字典中
            translated_dict = json.loads(content)
            final_dict.update(translated_dict)
            print(f"      ✅ 本批保留了 {len(translated_dict)} 个高质量视觉标签。")

        except Exception as e:
            print(f"      ❌ 第 {batch_num} 批处理失败: {e}，将跳过本批次。")
            # 打印出错时的调试信息
            if 'response' in locals():
                print(f"      [调试] API 返回: {response.text[:200]}")

        # ⚠️ 优雅的开发者要有并发控制意识：每次请求后休息1秒，防止被 API 判定为恶意攻击 (Rate Limit)
        time.sleep(1)

    print(f"✅ 所有批次处理完毕！大浪淘沙后共保留了 {len(final_dict)} 个高质量具象标签。")
    return final_dict

def vectorize_and_save(translated_dict):
    """阶段三：丢进 MobileCLIP 生成高维向量并落盘"""
    print("🧠 [阶段 3/3] 正在唤醒 MobileCLIP 提取 512 维隐空间特征...")
    model_name = "mobileclip_s2"
    checkpoint_path = "checkpoints/mobileclip_s2.pt"

    model, _, _ = mobileclip.create_model_and_transforms(model_name, pretrained=checkpoint_path)
    tokenizer = mobileclip.get_tokenizer(model_name)
    model.eval()

    chinese_tags = list(translated_dict.keys())
    english_prompts = [f"a photo of a {translated_dict[k]}" for k in chinese_tags]

    tokens = tokenizer(english_prompts)

    with torch.no_grad():
        text_features = model.encode_text(tokens)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)

    vectors = text_features.cpu().numpy().tolist()

    print("📦 正在打包最终的向量字典...")
    output_data = []
    for i, tag_zh in enumerate(chinese_tags):
        output_data.append({
            "tag": tag_zh,
            "vector": [round(num, 6) for num in vectors[i]]
        })

    with open(OUTPUT_VECTOR_FILE, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False)

    print(f"🎉 炼金大成功！终极向量脑库已保存至：{OUTPUT_VECTOR_FILE}")

if __name__ == "__main__":
    # 1. NLP 初筛
    pure_nouns = extract_visual_nouns(TXT_FILE, max_count=MAX_WORDS)

    if pure_nouns:
        # 2. 大模型视觉过滤 & 翻译
        en_dict = batch_translate(pure_nouns)

        if en_dict:
            # 🌟 核心新增：将 DeepSeek 的中间结果保存下来！
            with open(OUTPUT_DICT_FILE, "w", encoding="utf-8") as f:
                # indent=4 让 json 文件排版漂亮，方便你肉眼查看
                json.dump(en_dict, f, ensure_ascii=False, indent=4)
            print(f"💾 [监控] 已将 DeepSeek 过滤翻译后的中间词表保存至：{OUTPUT_DICT_FILE}")

            # 3. 向量化
            vectorize_and_save(en_dict)