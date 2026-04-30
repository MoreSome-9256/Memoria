#!/usr/bin/env python3
"""Fix remaining isar compat usages across view pages and services."""
import re, os, sys

def read(p):
    with open(p, encoding='utf-8') as f: return f.read()

def write(p, c):
    with open(p, 'w', encoding='utf-8') as f: f.write(c)

def add_imports(content, imports):
    for imp in imports:
        if imp not in content:
            m = list(re.finditer(r'^import [^\n]+;', content, re.MULTILINE))
            if m:
                pos = m[-1].end()
                content = content[:pos] + '\n' + imp + content[pos:]
    return content

def replace_or_warn(content, old, new, label):
    if old in content:
        return content.replace(old, new)
    print(f"  WARN [{label}]: pattern not found: {repr(old[:80])}")
    return content

errors = []

# ── album_search_page.dart ──────────────────────────────────────────────────
p = 'lib/view/pages/album_search_page.dart'
c = read(p)
c = replace_or_warn(c,
    "      final photos = (await PhotoService().isar.photoEntitys.getAll(ids))\n"
    "          .whereType<PhotoEntity>()\n"
    "          .toList(growable: false);",
    "      final photos = ObjectBoxService().store.box<PhotoEntity>()\n"
    "          .getMany(ids).whereType<PhotoEntity>().toList(growable: false);",
    "album_search getAll")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ album_search_page.dart")

# ── create_hub_page.dart ────────────────────────────────────────────────────
p = 'lib/view/pages/create_hub_page.dart'
c = read(p)
c = replace_or_warn(c,
    "    final covers = (await PhotoService().isar.photoEntitys.getAll(coverIds))",
    "    final covers = ObjectBoxService().store.box<PhotoEntity>().getMany(coverIds)",
    "create_hub getAll")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ create_hub_page.dart")

# ── config_page.dart ────────────────────────────────────────────────────────
p = 'lib/view/pages/config_page.dart'
c = read(p)
# There may be multiple isar usages; replace the specific block
c = replace_or_warn(c,
    "      final isar = PhotoService().isar;\n\n      EventEntity? eventEntity;\n",
    "      final store = ObjectBoxService().store;\n\n      EventEntity? eventEntity;\n",
    "config isar decl")
c = replace_or_warn(c,
    "        eventEntity = await isar.collection<EventEntity>().get(eventEntityId);",
    "        eventEntity = store.box<EventEntity>().get(eventEntityId);",
    "config get event")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ config_page.dart")

# ── digital_album_page.dart ─────────────────────────────────────────────────
p = 'lib/view/pages/digital_album_page.dart'
c = read(p)
c = replace_or_warn(c,
    "      final isar = PhotoService().isar;\n"
    "      final story = await isar.collection<StoryEntity>().get(widget.storyEntityId!);\n",
    "      final store = ObjectBoxService().store;\n"
    "      final story = store.box<StoryEntity>().get(widget.storyEntityId!);\n",
    "digital_album story get")
c = replace_or_warn(c,
    "      final photos = await isar.collection<PhotoEntity>().getAll(story.photoIds);",
    "      final photos = store.box<PhotoEntity>().getMany(story.photoIds);",
    "digital_album photos getAll")
c = replace_or_warn(c,
    "      await isar.writeTxn(() async {\n"
    "        await isar.collection<StoryEntity>().put(story);\n",
    "      store.runInTransaction(TxMode.write, () {\n"
    "        store.box<StoryEntity>().put(story);\n",
    "digital_album writeTxn story")
c = replace_or_warn(c,
    "          await isar.collection<PhotoEntity>().putAll(changedPhotos);\n",
    "          store.box<PhotoEntity>().putMany(changedPhotos);\n",
    "digital_album putAll photos")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ digital_album_page.dart")

# ── story_result_page.dart ──────────────────────────────────────────────────
p = 'lib/view/pages/story_result_page.dart'
c = read(p)
c = replace_or_warn(c,
    "      final isar = PhotoService().isar;\n"
    "      final story = await isar.collection<StoryEntity>().get(widget.storyEntityId!);",
    "      final story = ObjectBoxService().store.box<StoryEntity>().get(widget.storyEntityId!);",
    "story_result get story")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ story_result_page.dart")

# ── face_cluster_debug_page.dart ────────────────────────────────────────────
p = 'lib/view/pages/face_cluster_debug_page.dart'
c = read(p)
c = replace_or_warn(c,
    "    final isar = PhotoService().isar;\n"
    "    final faces = await isar.collection<FaceEntity>().where().findAll();\n"
    "    final photos = await isar.collection<PhotoEntity>().where().findAll();",
    "    final store = ObjectBoxService().store;\n"
    "    final faces = store.box<FaceEntity>().getAll();\n"
    "    final photos = store.box<PhotoEntity>().getAll();",
    "face_cluster_debug getAll")
c = add_imports(c, [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';"])
write(p, c); print("✓ face_cluster_debug_page.dart")

# ── event_detail_page.dart ──────────────────────────────────────────────────
p = 'lib/view/pages/event_detail_page.dart'
c = read(p)
# Check what the actual patterns look like
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'PhotoService().isar' in line:
        print(f"  event_detail line {i+1}: {line.rstrip()}")
        if i+1 < len(lines): print(f"  event_detail line {i+2}: {lines[i+1].rstrip()}")
        if i+2 < len(lines): print(f"  event_detail line {i+3}: {lines[i+2].rstrip()}")
        if i+3 < len(lines): print(f"  event_detail line {i+4}: {lines[i+3].rstrip()}")
        print()

# ── create_page.dart ────────────────────────────────────────────────────────
p = 'lib/view/pages/create_page.dart'
c = read(p)
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'PhotoService().isar' in line:
        print(f"  create_page line {i+1}: {line.rstrip()}")
        for j in range(1, 5):
            if i+j < len(lines): print(f"  create_page line {i+j+1}: {lines[i+j].rstrip()}")
        print()

# ── internvl_lab_page.dart ──────────────────────────────────────────────────
p = 'lib/view/pages/internvl_lab_page.dart'
c = read(p)
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'isar' in line.lower() and ('PhotoService' in line or 'collection<' in line or 'writeTxn' in line):
        print(f"  internvl_lab line {i+1}: {line.rstrip()}")
        for j in range(1, 5):
            if i+j < len(lines): print(f"  internvl_lab line {i+j+1}: {lines[i+j].rstrip()}")
        print()

# ── local_vlm_test_page.dart ────────────────────────────────────────────────
p = 'lib/view/pages/local_vlm_test_page.dart'
c = read(p)
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'isar' in line.lower() and ('PhotoService' in line or 'collection<' in line or 'writeTxn' in line):
        print(f"  local_vlm_test line {i+1}: {line.rstrip()}")
        for j in range(1, 5):
            if i+j < len(lines): print(f"  local_vlm_test line {i+j+1}: {lines[i+j].rstrip()}")
        print()

# ── story_video_page.dart ───────────────────────────────────────────────────
p = 'lib/view/pages/story_video_page.dart'
c = read(p)
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'isar' in line.lower() and ('PhotoService' in line or 'collection<' in line or 'faceEntitys' in line or 'writeTxn' in line):
        print(f"  story_video line {i+1}: {line.rstrip()}")
        for j in range(1, 6):
            if i+j < len(lines): print(f"  story_video line {i+j+1}: {lines[i+j].rstrip()}")
        print()

# ── home_page.dart ──────────────────────────────────────────────────────────
p = 'lib/view/pages/home_page.dart'
c = read(p)
lines = c.split('\n')
for i, line in enumerate(lines):
    if 'isar' in line.lower() and ('PhotoService' in line or 'photoEntitys' in line or 'collection<' in line):
        print(f"  home_page line {i+1}: {line.rstrip()}")
        for j in range(1, 4):
            if i+j < len(lines): print(f"  home_page line {i+j+1}: {lines[i+j].rstrip()}")
        print()
