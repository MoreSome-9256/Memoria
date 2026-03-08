import json
import os
import time

import requests


DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "")

MODEL_NAME = "deepseek-chat"
TAGS_FILE = "ai_tools/expanded_tags_vectors.json"
TRANSLATION_DICT_FILE = "ai_tools/ds_filtered_dict.json"
COMMON_WORD_LIST_FILE = "ai_tools/现代汉语常用词表.txt"
OUTPUT_FILE = "ai_tools/expanded_tags_taxonomy.json"
CHECKPOINT_FILE = "ai_tools/expanded_tags_taxonomy_checkpoint.json"
BATCH_SIZE = 100
REQUEST_DELAY_SECONDS = 1.0
MAX_RETRIES = 3
REQUEST_TIMEOUT_SECONDS = 120
FALLBACK_CATEGORY = "抽象与其他"

CATEGORY_DEFINITIONS = {
    "人物与群体": "人物身份、职业、家庭角色、群体称呼、可见的人物主体。",
    "美食与饮品": "食物、菜品、主食、小吃、零食、饮料、餐饮相关主体。",
    "建筑与场所": "建筑物、室内外场所、公共空间、城市地点、景点、园区。",
    "自然与风光": "山川河流、天空天气、地貌、自然景观、风景场景。",
    "日常物品": "器具、工具、交通工具、家具、电器、证件、衣物等具体物件。",
    "动物与植物": "动物、植物、花草、树木、果实、种子、生物体。",
    "活动与事件": "动作、运动、表演、节庆、典礼、聚会、可被拍到的事件。",
    "抽象与其他": "以上都不明显匹配时的兜底类别，或抽象但仍需保留的标签。",
}


def load_json(path):
    with open(path, "r", encoding="utf-8") as file:
        return json.load(file)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)


def load_common_word_order(path):
    common_word_order = {}
    with open(path, "r", encoding="utf-8") as file:
        for line in file:
            parts = line.strip().split()
            if len(parts) < 3:
                continue
            try:
                common_word_order[parts[0]] = int(parts[2])
            except ValueError:
                continue
    return common_word_order


def build_base_records():
    vector_records = load_json(TAGS_FILE)
    translation_dict = load_json(TRANSLATION_DICT_FILE)
    common_word_order = load_common_word_order(COMMON_WORD_LIST_FILE)
    fallback_order = 10**9

    records = []
    for item in vector_records:
        tag = item["tag"]
        records.append(
            {
                "tag": tag,
                "translation": translation_dict.get(tag, ""),
                "vector": item["vector"],
                "common_word_order": common_word_order.get(tag, fallback_order),
            }
        )
    return records


def load_checkpoint():
    if not os.path.exists(CHECKPOINT_FILE):
        return {}
    checkpoint = load_json(CHECKPOINT_FILE)
    if not isinstance(checkpoint, dict):
        return {}
    return checkpoint


def save_checkpoint(category_map):
    save_json(CHECKPOINT_FILE, category_map)


def build_system_prompt():
    category_lines = [
        f"- {category}: {description}"
        for category, description in CATEGORY_DEFINITIONS.items()
    ]
    joined_categories = "\n".join(category_lines)
    return (
        "你是一个给手机相册视觉标签做分层分类的专家。\n"
        "用户会给你一批中文标签，以及可选的英文翻译提示。\n"
        "请为每个标签从下面这些大类中严格选择且只能选择一个：\n"
        f"{joined_categories}\n\n"
        "分类规则：\n"
        "1. 目标是相册语义展示，不是词典学定义。优先判断这类词在照片中最常作为哪种主体被展示。\n"
        "2. 如果一个词既像场所又像活动，优先选择更适合在相册 UI 中做分组导航的大类。\n"
        "3. 如果拿不准，使用 抽象与其他。\n"
        "4. 绝对不要输出任何额外说明，只返回 JSON 对象，键为原始中文标签，值为大类名称。\n"
        "5. 不要遗漏任何输入标签。"
    )


def classify_batch(batch):
    url = "https://api.deepseek.com/chat/completions"
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json",
    }

    # 🌟 核心修复：构建一个精简版的字典给 AI 看，剥离庞大的 vector
    simplified_batch = {
        item["tag"]: item["translation"] for item in batch
    }

    payload = {
        "model": MODEL_NAME,
        "messages": [
            {"role": "system", "content": build_system_prompt()},
            # 喂给 AI 这个干净的、只包含中英文映射的字典
            {"role": "user", "content": json.dumps(simplified_batch, ensure_ascii=False)},
        ],
        "response_format": {"type": "json_object"},
    }

    response = requests.post(
        url,
        headers=headers,
        json=payload,
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    # 如果再出错，打印出错误明细方便调试
    if response.status_code != 200:
        print(f"  [API Error Detail]: {response.text}")
    response.raise_for_status()

    content = response.json()["choices"][0]["message"]["content"]
    return json.loads(content)


def normalize_category_map(raw_category_map, batch):
    normalized = {}
    valid_categories = set(CATEGORY_DEFINITIONS)

    for item in batch:
        tag = item["tag"]
        category = raw_category_map.get(tag, FALLBACK_CATEGORY)
        if category not in valid_categories:
            category = FALLBACK_CATEGORY
        normalized[tag] = category

    return normalized


def classify_all_tags(records):
    if not DEEPSEEK_API_KEY:
        raise RuntimeError("请先设置环境变量 DEEPSEEK_API_KEY")

    category_map = load_checkpoint()
    remaining_records = [record for record in records if record["tag"] not in category_map]

    if not remaining_records:
        print("所有标签都已完成分类，将直接生成最终文件。")
        return category_map

    total_batches = (len(remaining_records) + BATCH_SIZE - 1) // BATCH_SIZE
    print(f"准备处理 {len(remaining_records)} 个待分类标签，共 {total_batches} 批。")

    for batch_start in range(0, len(remaining_records), BATCH_SIZE):
        batch = remaining_records[batch_start: batch_start + BATCH_SIZE]
        batch_index = batch_start // BATCH_SIZE + 1
        print(f"处理第 {batch_index}/{total_batches} 批，本批 {len(batch)} 个标签。")

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                raw_category_map = classify_batch(batch)
                normalized_map = normalize_category_map(raw_category_map, batch)
                category_map.update(normalized_map)
                save_checkpoint(category_map)
                print(f"  第 {batch_index} 批完成。")
                break
            except Exception as error:
                print(f"  第 {batch_index} 批第 {attempt} 次失败: {error}")
                if attempt == MAX_RETRIES:
                    raise
                time.sleep(REQUEST_DELAY_SECONDS * attempt)

        time.sleep(REQUEST_DELAY_SECONDS)

    return category_map


def build_output_records(records, category_map):
    output_records = []
    for record in records:
        output_records.append(
            {
                "tag": record["tag"],
                "category": category_map.get(record["tag"], FALLBACK_CATEGORY),
                "translation": record["translation"],
                "common_word_order": record["common_word_order"],
                "vector": record["vector"],
            }
        )
    return output_records


def main():
    records = build_base_records()
    print(f"已加载 {len(records)} 个标签，开始构建分层语义词库。")

    category_map = classify_all_tags(records)
    output_records = build_output_records(records, category_map)
    save_json(OUTPUT_FILE, output_records)

    print(f"分类完成，输出文件已保存到: {OUTPUT_FILE}")
    print(f"断点文件已保存到: {CHECKPOINT_FILE}")


if __name__ == "__main__":
    main()