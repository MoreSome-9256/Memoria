import 'package:flutter/material.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/vo/photo.dart';
import '../../service/story_queue_service.dart';
import '../../utils/media_type_helper.dart';
import '../../utils/tag_sanitizer.dart';
import '../../utils/ocr_policy.dart';
import '../widgets/media_thumbnail.dart';
import '../pages/story_queue_page.dart';

class SelectPhotosPage extends StatefulWidget {
  final List<PhotoEntity> photos;
  final String topic;

  const SelectPhotosPage({
    super.key,
    required this.photos,
    required this.topic,
  });

  @override
  State<SelectPhotosPage> createState() => _SelectPhotosPageState();
}

class _SelectPhotosPageState extends State<SelectPhotosPage> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    // 默认全部勾选
    _selectedIds = widget.photos.map((p) => p.id).toSet();
  }

  Photo _mapPhotoEntityToPhoto(PhotoEntity photo) {
    return Photo(
      id: photo.assetId,
      location:
          photo.locationName ??
          photo.district ??
          photo.city ??
          photo.province ??
          '未知地点',
      path: photo.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
      tags: TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]),
      caption: photo.aiCaption?.trim(),
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: photo.ocrTags ?? const <String>[],
        text: photo.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]),
      isSelected: true,
      mediaKind: photo.mediaKind,
      thumbnailBytes: photo.thumbnailBytes,
    );
  }

  void _handleNextStep() {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少保留一张照片哦')));
      return;
    }

    final selectedEntities = widget.photos
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    final mappedPhotos = selectedEntities.map(_mapPhotoEntityToPhoto).toList();

    StoryQueueService().replacePhotos(
      mappedPhotos,
      semanticSearchQuery: widget.topic,
      title: widget.topic,
      subtitle: '来自对话回忆',
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const StoryQueuePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          '确认记忆碎片',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _handleNextStep,
            child: const Text(
              '下一步',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 255, 64, 129),
              ),
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: widget.photos.length,
        itemBuilder: (context, index) {
          final photo = widget.photos[index];
          final isSelected = _selectedIds.contains(photo.id);
          return GestureDetector(
            onTap: () {
              setState(() {
                isSelected
                    ? _selectedIds.remove(photo.id)
                    : _selectedIds.add(photo.id);
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MediaThumbnail(
                    path: photo.path,
                    assetId: photo.assetId,
                    kind: MediaTypeHelper.fromStorageValue(
                      photo.mediaKind,
                      path: photo.path,
                    ),
                    thumbnailBytes: photo.thumbnailBytes,
                    fit: BoxFit.cover,
                  ),
                ),
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color.fromARGB(255, 255, 64, 129),
                        width: 3,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
