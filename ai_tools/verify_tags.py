"""
验证 expanded_tags_vectors.json 标签质量
用法：
    python ai_tools/verify_tags.py 测试图片1.jpg 测试图片2.jpg ...

会对每张图片输出 Top-10 最匹配的中文标签和相似度分数。
"""
import sys
import json
import os
import torch
from PIL import Image
import mobileclip


# ============ 配置 ============
MODEL_NAME = "mobileclip_s2"
CHECKPOINT = "checkpoints/mobileclip_s2.pt"
TAGS_FILE = "ai_tools/expanded_tags_vectors.json"
TAXONOMY_FILE = "ai_tools/expanded_tags_taxonomy.json"
COMMON_WORD_LIST_FILE = "ai_tools/现代汉语常用词表.txt"
TRANSLATION_DICT_FILE = "ai_tools/ds_filtered_dict.json"
TOP_K = 15
TEMPERATURE = 0.01
NMS_THRESHOLD = 0.92
DISPLAY_SCORE_GAP = 0.04
MAX_DISPLAY_TAGS = 3
SCORE_BUCKET_DECIMALS = 2
CATEGORY_EMOJIS = {
    "人物与群体": "👤",
    "美食与饮品": "🍔",
    "建筑与场所": "🏢",
    "自然与风光": "🌲",
    "日常物品": "🧸",
    "动物与植物": "🐕",
    "活动与事件": "🏃",
    "抽象与其他": "🧩",
}
# ==============================


def load_tag_vectors(path):
    """加载预计算的标签向量"""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    tags = [item["tag"] for item in data]
    vectors = torch.tensor([item["vector"] for item in data], dtype=torch.float32)
    # 确保归一化
    vectors = vectors / vectors.norm(dim=-1, keepdim=True)
    return tags, vectors


def load_common_word_order(path):
    """加载常用词表序号，序号越小表示词在常用词表中越靠前。"""
    common_word_order = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 3:
                continue
            word = parts[0]
            try:
                common_word_order[word] = int(parts[2])
            except ValueError:
                continue
    return common_word_order


def load_translation_dict(path):
    """加载中文标签到英文提示词的映射，便于分析翻译坍塌。"""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_tag_metadata(tags, common_word_order, translation_dict):
    """为每个标签补充常用词表序号和翻译信息。"""
    fallback_order = 10**9
    return [
        {
            "tag": tag,
            "length": len(tag),
            "common_word_order": common_word_order.get(tag, fallback_order),
            "translation": translation_dict.get(tag, ""),
            "category": "抽象与其他",
        }
        for tag in tags
    ]


def load_tag_records():
    """优先加载带 taxonomy 的结构化标签库，否则回退到基础向量库。"""
    if os.path.exists(TAXONOMY_FILE):
        with open(TAXONOMY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        tags = [item["tag"] for item in data]
        vectors = torch.tensor([item["vector"] for item in data], dtype=torch.float32)
        vectors = vectors / vectors.norm(dim=-1, keepdim=True)
        metadata = [
            {
                "tag": item["tag"],
                "length": len(item["tag"]),
                "common_word_order": item.get("common_word_order", 10**9),
                "translation": item.get("translation", ""),
                "category": item.get("category", "抽象与其他"),
            }
            for item in data
        ]
        return tags, vectors, metadata, TAXONOMY_FILE

    tags, vectors = load_tag_vectors(TAGS_FILE)
    common_word_order = load_common_word_order(COMMON_WORD_LIST_FILE)
    translation_dict = load_translation_dict(TRANSLATION_DICT_FILE)
    metadata = build_tag_metadata(tags, common_word_order, translation_dict)
    return tags, vectors, metadata, TAGS_FILE


def group_tags_by_category(selected_tags):
    """按大类聚合已选中的小类标签，保留出现顺序。"""
    grouped = {}
    for item in selected_tags:
        category = item["category"]
        if category not in grouped:
            grouped[category] = []
        grouped[category].append(item)
    return grouped


def select_core_tags(similarities, tag_vectors, tag_metadata):
    """用温度 softmax 和文本向量 NMS 选出非冗余核心标签。"""
    probs = torch.softmax(similarities / TEMPERATURE, dim=0)

    top1_score = similarities.max().item()
    display_threshold = top1_score - DISPLAY_SCORE_GAP

    candidates = []
    for idx, score_tensor in enumerate(similarities):
        score = score_tensor.item()
        if score < display_threshold:
            continue
        meta = tag_metadata[idx]
        candidates.append(
            {
                "idx": idx,
                "score": score,
                "score_bucket": round(score, SCORE_BUCKET_DECIMALS),
                "length": meta["length"],
                "common_word_order": meta["common_word_order"],
                "tag": meta["tag"],
            }
        )

    candidates.sort(
        key=lambda item: (
            -item["score_bucket"],
            -item["length"],
            item["common_word_order"],
            -item["score"],
            item["tag"],
        )
    )

    selected = []
    selected_indices = []

    for candidate in candidates:
        idx = candidate["idx"]
        score = candidate["score"]
        current_vector = tag_vectors[idx]
        current_meta = tag_metadata[idx]

        is_redundant = False
        redundancy_score = 0.0
        if selected_indices:
            selected_vectors = tag_vectors[selected_indices]
            similarity_to_selected = selected_vectors @ current_vector
            redundancy_score = similarity_to_selected.max().item()
            is_redundant = redundancy_score > NMS_THRESHOLD

        if is_redundant:
            continue

        selected.append(
            {
                "tag": current_meta["tag"],
                "score": score,
                "prob": probs[idx].item(),
                "redundancy_score": redundancy_score,
                "common_word_order": current_meta["common_word_order"],
                "translation": current_meta["translation"],
                "category": current_meta["category"],
            }
        )
        selected_indices.append(idx)

        if len(selected) >= MAX_DISPLAY_TAGS:
            break

    return probs, selected


def main():
    if len(sys.argv) < 2:
        print("用法: python verify_tags.py <图片路径1> [图片路径2] ...")
        print("示例: python verify_tags.py test_beach.jpg test_cat.jpg")
        sys.exit(1)

    image_paths = sys.argv[1:]

    # 1. 加载模型
    print(f"正在加载 {MODEL_NAME} ...")
    model, _, preprocess = mobileclip.create_model_and_transforms(
        MODEL_NAME, pretrained=CHECKPOINT
    )
    model.eval()

    # 2. 加载标签向量
    tags, tag_vectors, tag_metadata, metadata_source = load_tag_records()
    print(f"正在加载标签库: {metadata_source}")
    print(f"共 {len(tags)} 个标签\n")

    # 3. 对每张图片计算匹配度
    for img_path in image_paths:
        try:
            img = Image.open(img_path).convert("RGB")
        except Exception as e:
            print(f"[跳过] 无法打开 {img_path}: {e}\n")
            continue

        img_tensor = preprocess(img).unsqueeze(0)

        with torch.no_grad():
            img_features = model.encode_image(img_tensor)
            img_features = img_features / img_features.norm(dim=-1, keepdim=True)

        # 余弦相似度 = 直接点积（因为都已归一化）
        similarities = (img_features @ tag_vectors.T).squeeze(0)
        probs, selected_tags = select_core_tags(similarities, tag_vectors, tag_metadata)
        top_values, top_indices = similarities.topk(TOP_K)

        print(f"{'='*50}")
        print(f"图片: {img_path}")
        print(f"{'='*50}")
        print(f"{'排名':<4} {'标签':<10} {'相似度':<10} {'Softmax':<10}")
        print(f"{'-'*44}")
        for rank, (val, idx) in enumerate(zip(top_values, top_indices), 1):
            score = val.item()
            tag_index = idx.item()
            tag = tags[tag_index]
            prob = probs[tag_index].item() * 100
            bar = "█" * max(0, int(score * 40))
            print(f"  {rank:<3} {tag:<10} {score:.4f}   {prob:>6.2f}% {bar}")
        print()

        print(
            f"📸 智能提取到 {len(selected_tags)} 个非冗余核心标签 "
            f"(tau={TEMPERATURE}, nms={NMS_THRESHOLD}, top_gap={DISPLAY_SCORE_GAP}, "
            f"bucket=round(score,{SCORE_BUCKET_DECIMALS}), order=bucket>len>commonness>score)："
        )
        for item in selected_tags:
            print(
                f" 🏷️ {item['tag']:<8} | 原始余弦: {item['score']:.4f} "
                f"| Softmax置信度: {item['prob'] * 100:>6.2f}% "
                f"| 常用词序: {item['common_word_order']} "
                f"| 大类: {item['category']}"
            )

        grouped_tags = group_tags_by_category(selected_tags)
        if grouped_tags:
            print("\n🧭 双层主题展示：")
            for category, items in grouped_tags.items():
                emoji = CATEGORY_EMOJIS.get(category, "🏷️")
                child_tags = "、".join(item["tag"] for item in items)
                print(f" {emoji} {category}: {child_tags}")
        print()


if __name__ == "__main__":
    main()
