import torch
import mobileclip
import json
import os

# 🌟 1. 我们的“现成资料”：高频中文生活标签 -> MobileCLIP 英文提示词映射字典
# （为了快速验证跑通全链路，这里精选了数十个代表性词汇，后续可无缝扩充至 3000+）
CHINESE_TO_ENGLISH_TAGS = {
    # 🏙️ 场景与地理 (Places365 提炼)
    "海滩": "beach",
    "雪山": "snow mountain",
    "夜市": "night market",
    "高铁站": "high-speed railway station",
    "办公室": "office",
    "咖啡馆": "coffee shop",

    # 🍔 中华饮食 (本土化重塑)
    "火锅": "hot pot",
    "烧烤": "barbecue",
    "奶茶": "bubble tea",
    "饺子": "dumplings",

    # 🧸 长尾物件 (LVIS 提炼)
    "猫咪": "cat",
    "小狗": "dog",
    "电动车": "electric scooter",
    "充电宝": "power bank",

    # 🎉 事件与情绪 (活动抽象概念)
    "年夜饭": "new year's eve dinner",
    "毕业典礼": "graduation ceremony",
    "微笑": "smiling face",
    "自拍": "taking a selfie",
    "合影": "group photo",

    # 📄 实用证件 (Apple Taxonomy 启发)
    "身份证": "ID card",
    "发票": "invoice receipt",
    "护照": "passport"
}

def build_vector_dictionary():
    model_name = "mobileclip_s2"
    checkpoint_path = "checkpoints/mobileclip_s2.pt"
    output_path = "ai_tools/tags_vectors.json"

    print(f"--- 🧠 正在唤醒 MobileCLIP 文本编码器 ({model_name}) ---")
    model, _, _ = mobileclip.create_model_and_transforms(model_name, pretrained=checkpoint_path)
    tokenizer = mobileclip.get_tokenizer(model_name)
    model.eval()

    chinese_tags = list(CHINESE_TO_ENGLISH_TAGS.keys())
    # 🌟 核心工程魔法：套用标准 Prompt 模板提升零样本召回率
    english_prompts = [f"a photo of a {CHINESE_TO_ENGLISH_TAGS[k]}" for k in chinese_tags]

    print(f"--- 🧬 正在将 {len(chinese_tags)} 个中文标签转化为 512 维高维向量 ---")
    tokens = tokenizer(english_prompts)

    with torch.no_grad():
        # 提取特征
        text_features = model.encode_text(tokens)
        # ⚠️ 极其重要的一步：向量归一化！
        # 只有经过 L2 归一化，端侧使用点积(Dot Product)算出来的才是余弦相似度！
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)

    # 转化为普通的 Python 浮点数列表
    vectors = text_features.cpu().numpy().tolist()

    print("--- 📦 正在打包字典 ---")
    output_data = []
    for i, tag_zh in enumerate(chinese_tags):
        output_data.append({
            "tag": tag_zh,
            "vector": [round(num, 6) for num in vectors[i]] # 保留6位小数，极限压缩体积
        })

    # 保存为 JSON 文件供 Flutter 初始化读取
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False)

    print(f"--- 🎉 大功告成！向量字典已保存至: {output_path} ---")
    print("💡 提示：将此 JSON 放入 Flutter 的 assets 中，App 首次启动时即可将其灌入 sqlite-vec 数据库！")

if __name__ == "__main__":
    build_vector_dictionary()