#!/usr/bin/env python3
"""Fix remaining isar compat usages in view pages."""
import re

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

OB_IMPORTS = [
    "import '../../objectbox.g.dart';",
    "import '../../storage/objectbox/objectbox_service.dart';",
]

def ob_query_desc(limit, extra_cond=''):
    cond = extra_cond if extra_cond else ''
    return (
        f"    final _photoBox = ObjectBoxService().store.box<PhotoEntity>();\n"
        f"    final _q = _photoBox.query({cond})\n"
        f"        .order(PhotoEntity_.timestamp, flags: Order.descending).build();\n"
        f"    _q.limit = {limit};\n"
        f"    final recentCandidates = _q.find();\n"
        f"    _q.close();"
    )

# ── create_page.dart ────────────────────────────────────────────────────────
p = 'lib/view/pages/create_page.dart'
c = read(p)
c = c.replace(
    "    final photos = await PhotoService().isar\n"
    "        .collection<PhotoEntity>()\n"
    "        .filter()\n"
    "        .isAiAnalyzedEqualTo(true)\n"
    "        .sortByTimestampDesc()\n"
    "        .findAll();",
    "    final _pb = ObjectBoxService().store.box<PhotoEntity>();\n"
    "    final _q = _pb.query(PhotoEntity_.isAiAnalyzed.equals(true))\n"
    "        .order(PhotoEntity_.timestamp, flags: Order.descending).build();\n"
    "    final photos = _q.find();\n"
    "    _q.close();"
)
c = add_imports(c, OB_IMPORTS)
write(p, c); print("✓ create_page.dart")

# ── internvl_lab_page.dart ──────────────────────────────────────────────────
# The isar variable is declared but we need to see how it's used further
p = 'lib/view/pages/internvl_lab_page.dart'
c = read(p)
lines = c.split('\n')
# Find all isar usages
isar_lines = [(i, line) for i, line in enumerate(lines) if 'isar' in line]
for i, line in isar_lines:
    print(f"  internvl_lab {i+1}: {line}")
# Just replace the declaration - the isar variable may not be used further
c = c.replace(
    "    final isar = PhotoService().isar;\n",
    "    // ObjectBox store available via ObjectBoxService().store\n"
)
# Check if isar is actually used
if 'isar.' in c or 'isar\n' in c:
    print("  WARNING: isar still used in internvl_lab_page.dart")
c = add_imports(c, OB_IMPORTS)
write(p, c); print("✓ internvl_lab_page.dart")

# ── local_vlm_test_page.dart ────────────────────────────────────────────────
p = 'lib/view/pages/local_vlm_test_page.dart'
c = read(p)
c = c.replace(
    "    final isar = PhotoService().isar;\n",
    "    // ObjectBox store available via ObjectBoxService().store\n"
)
if 'isar.' in c:
    print("  WARNING: isar still used in local_vlm_test_page.dart")
c = add_imports(c, OB_IMPORTS)
write(p, c); print("✓ local_vlm_test_page.dart")

# ── story_video_page.dart ───────────────────────────────────────────────────
p = 'lib/view/pages/story_video_page.dart'
c = read(p)
c = c.replace(
    "      final isar = PhotoService().isar;\n"
    "\n"
    "      for (int i = 0; i < _localSections.length; i++) {\n"
    "        final photo = _localSections[i].photo;\n"
    "\n"
    "        // 🚀 极速查询：根据 assetId 去 FaceEntity 表里捞出这张照片对应的所有人脸\n"
    "        final faces = await isar.faceEntitys\n"
    "            .filter()\n"
    "            .assetIdEqualTo(photo.id)\n"
    "            .findAll();",
    "      final _faceBox = ObjectBoxService().store.box<FaceEntity>();\n"
    "\n"
    "      for (int i = 0; i < _localSections.length; i++) {\n"
    "        final photo = _localSections[i].photo;\n"
    "\n"
    "        // 🚀 极速查询：根据 assetId 去 FaceEntity 表里捞出这张照片对应的所有人脸\n"
    "        final _fq = _faceBox.query(FaceEntity_.assetId.equals(photo.id)).build();\n"
    "        final faces = _fq.find();\n"
    "        _fq.close();"
)
c = add_imports(c, OB_IMPORTS)
write(p, c); print("✓ story_video_page.dart")

# ── home_page.dart ──────────────────────────────────────────────────────────
p = 'lib/view/pages/home_page.dart'
c = read(p)

# Replace first isar block (_loadRecentPhotos)
c = c.replace(
    "    final isar = PhotoService().isar;\n"
    "\n"
    "    var recentCandidates = await isar.photoEntitys\n"
    "        .where()\n"
    "        .sortByTimestampDesc()\n"
    "        .limit(100)\n"
    "        .findAll();",
    "    final _pb = ObjectBoxService().store.box<PhotoEntity>();\n"
    "    final _q = _pb.query().order(PhotoEntity_.timestamp, flags: Order.descending).build();\n"
    "    _q.limit = 100;\n"
    "    var recentCandidates = _q.find();\n"
    "    _q.close();"
)

# Replace second isar block (_generateDiscoverCards)
c = c.replace(
    "    final isar = PhotoService().isar;\n"
    "    final now = DateTime.now();\n",
    "    final _photoBox = ObjectBoxService().store.box<PhotoEntity>();\n"
    "    final now = DateTime.now();\n"
)

# Replace timestampBetween queries (3 occurrences)
def replace_timestamp_between(content, var_name):
    old = (
        f"      final {var_name} = await isar.photoEntitys\n"
        f"          .filter()\n"
        f"          .timestampBetween(start, end)\n"
        f"          .findAll();"
    )
    new = (
        f"      final _tq = _photoBox.query(\n"
        f"        PhotoEntity_.timestamp.between(start, end)).build();\n"
        f"      final {var_name} = _tq.find();\n"
        f"      _tq.close();"
    )
    if old in content:
        return content.replace(old, new, 1)
    print(f"  WARN: timestampBetween pattern for '{var_name}' not found")
    return content

c = replace_timestamp_between(c, 'photos')
c = replace_timestamp_between(c, 'photos')
c = replace_timestamp_between(c, 'photos')

# Replace _buildContentRuleCards recentPhotos
c = c.replace(
    "    final recentPhotos = await isar.photoEntitys\n"
    "        .where()\n"
    "        .sortByTimestampDesc()\n"
    "        .limit(500)\n"
    "        .findAll();",
    "    final _cq = _photoBox.query().order(PhotoEntity_.timestamp, flags: Order.descending).build();\n"
    "    _cq.limit = 500;\n"
    "    final recentPhotos = _cq.find();\n"
    "    _cq.close();"
)

# Replace _buildLocationRuleCards recentPhotos
c = c.replace(
    "    final recentPhotos = await isar.photoEntitys\n"
    "        .where()\n"
    "        .sortByTimestampDesc()\n"
    "        .limit(1000)\n"
    "        .findAll();",
    "    final _lq = _photoBox.query().order(PhotoEntity_.timestamp, flags: Order.descending).build();\n"
    "    _lq.limit = 1000;\n"
    "    final recentPhotos = _lq.find();\n"
    "    _lq.close();"
)

c = add_imports(c, OB_IMPORTS)
write(p, c); print("✓ home_page.dart")

# ── Verify no more isar usages ──────────────────────────────────────────────
import os
view_pages = [
    'lib/view/pages/album_page.dart',
    'lib/view/pages/album_search_page.dart',
    'lib/view/pages/config_page.dart',
    'lib/view/pages/create_hub_page.dart',
    'lib/view/pages/create_page.dart',
    'lib/view/pages/digital_album_page.dart',
    'lib/view/pages/event_detail_page.dart',
    'lib/view/pages/face_cluster_debug_page.dart',
    'lib/view/pages/home_page.dart',
    'lib/view/pages/internvl_lab_page.dart',
    'lib/view/pages/local_vlm_test_page.dart',
    'lib/view/pages/story_result_page.dart',
    'lib/view/pages/story_video_page.dart',
]
print("\n=== Remaining isar usages ===")
for fp in view_pages:
    c = read(fp)
    hits = [line.strip() for line in c.split('\n') 
            if ('PhotoService().isar' in line or 
                ('isar.' in line and ('collection<' in line or 'writeTxn' in line or 
                 'photoEntitys' in line or 'faceEntitys' in line)))]
    if hits:
        print(f"  {fp}:")
        for h in hits: print(f"    {h}")
