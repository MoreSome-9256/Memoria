// 创作流程页面，承载故事生成的具体操作步骤。

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../data/tag_taxonomy_v2.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/mobileclip_embedding_service.dart';
import '../../service/semantic_matching_service.dart';
import '../../storage/vector_index/photo_embedding_index_repository.dart';
import '../../utils/ocr_policy.dart';
import '../../utils/tag_sanitizer.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../widgets/path_image.dart';
import 'story_config_page.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

class _CreatePhotoSearchRecord {
  const _CreatePhotoSearchRecord({
    required this.photoId,
    required this.timestamp,
    required this.isProbablyScreenshot,
    required this.locationParts,
    required this.tags,
  });

  factory _CreatePhotoSearchRecord.fromEntity(PhotoEntity photo) {
    return _CreatePhotoSearchRecord(
      photoId: photo.id,
      timestamp: photo.timestamp,
      isProbablyScreenshot: photo.isProbablyScreenshot,
      locationParts: <String>[
        photo.locationName ?? '',
        photo.district ?? '',
        photo.city ?? '',
        photo.province ?? '',
      ],
      tags: TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]),
    );
  }

  final int photoId;
  final int timestamp;
  final bool isProbablyScreenshot;
  final List<String> locationParts;
  final List<String> tags;

  String get locationText => locationParts.join(' ');
}

class _CreateSearchFilterRequest {
  const _CreateSearchFilterRequest({
    required this.query,
    required this.locations,
    required this.records,
  });

  final String query;
  final List<String> locations;
  final List<_CreatePhotoSearchRecord> records;
}

class _CreateSearchFilterResult {
  const _CreateSearchFilterResult({
    required this.candidateIds,
    required this.remainingQuery,
    required this.matchedLocations,
    this.targetYear,
  });

  final List<int> candidateIds;
  final String remainingQuery;
  final List<String> matchedLocations;
  final String? targetYear;
}

class _CreateSemanticScoringInput {
  const _CreateSemanticScoringInput({
    required this.photoId,
    required this.tags,
    required this.imageEmbedding,
  });

  final int photoId;
  final List<String> tags;
  final List<double> imageEmbedding;
}

class _CreateSemanticScoringRequest {
  const _CreateSemanticScoringRequest({
    required this.inputs,
    required this.textVector,
    required this.query,
    required this.taxonomyLabel,
    required this.minSimilarity,
    required this.strictTaxonomyThreshold,
    required this.maxResults,
  });

  final List<_CreateSemanticScoringInput> inputs;
  final List<double> textVector;
  final String query;
  final String? taxonomyLabel;
  final double minSimilarity;
  final double strictTaxonomyThreshold;
  final int maxResults;
}

class _CreateSemanticScoringResult {
  const _CreateSemanticScoringResult({
    required this.matchedIds,
    required this.preview,
    required this.filteredCount,
    required this.scoredCount,
  });

  final List<int> matchedIds;
  final String preview;
  final int filteredCount;
  final int scoredCount;
}

class _CreateVisualTagFallbackRequest {
  const _CreateVisualTagFallbackRequest({
    required this.records,
    required this.query,
    required this.taxonomyLabel,
    required this.maxResults,
  });

  final List<_CreatePhotoSearchRecord> records;
  final String query;
  final String? taxonomyLabel;
  final int maxResults;
}

class _CreateLaunchPhotoRecord {
  const _CreateLaunchPhotoRecord({
    required this.assetId,
    required this.location,
    required this.path,
    required this.timestamp,
    required this.tags,
    required this.caption,
    required this.ocrSummary,
    required this.ocrTags,
    required this.mediaKind,
    required this.thumbnailBytes,
  });

  factory _CreateLaunchPhotoRecord.fromEntity(PhotoEntity photo) {
    return _CreateLaunchPhotoRecord(
      assetId: photo.assetId,
      location:
          photo.locationName ??
          photo.district ??
          photo.city ??
          photo.province ??
          '未知地点',
      path: photo.path,
      timestamp: photo.timestamp,
      tags: TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]),
      caption: photo.aiCaption?.trim(),
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: photo.ocrTags ?? const <String>[],
        text: photo.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]),
      mediaKind: photo.mediaKind,
      thumbnailBytes: photo.thumbnailBytes,
    );
  }

  final String assetId;
  final String location;
  final String path;
  final int timestamp;
  final List<String> tags;
  final String? caption;
  final String? ocrSummary;
  final List<String> ocrTags;
  final String mediaKind;
  final Uint8List? thumbnailBytes;
}

class _CreateLaunchRequest {
  const _CreateLaunchRequest({required this.records, required this.themeTitle});

  final List<_CreateLaunchPhotoRecord> records;
  final String themeTitle;
}

class _CreateLaunchResult {
  const _CreateLaunchResult({
    required this.photos,
    required this.startDate,
    required this.endDate,
  });

  final List<Photo> photos;
  final DateTime startDate;
  final DateTime endDate;

  int get startYear => startDate.year;
}

const Set<String> _createSemanticStopWords = <String>{
  '照片',
  '图片',
  '相片',
  '相册',
  '回忆',
  '那次',
  '那年',
  '那天',
  '时候',
  '一下',
  '看看',
  '想看',
  '一下子',
  '一下下',
  '给我',
  '帮我',
};

Set<String> _buildCreateLocationDictionary(
  List<_CreatePhotoSearchRecord> records,
) {
  final allLocations = <String>{};
  for (final record in records) {
    for (final loc in record.locationParts) {
      if (loc.trim().isEmpty) {
        continue;
      }
      final cleanLoc = loc.trim();
      allLocations.add(cleanLoc);
      final strippedLoc = cleanLoc.replaceAll(RegExp(r'[省市自治区县盟旗]'), '').trim();
      if (strippedLoc.length >= 2) {
        allLocations.add(strippedLoc);
      }
    }
  }
  return allLocations;
}

_CreateSearchFilterResult _filterCreateSearchCandidates(
  _CreateSearchFilterRequest request,
) {
  var remainingQuery = request.query.trim();
  String? targetYear;
  final matchedLocations = <String>[];

  final yearMatch = RegExp(r'(20\d{2})').firstMatch(remainingQuery);
  if (yearMatch != null) {
    targetYear = yearMatch.group(0);
    remainingQuery = remainingQuery.replaceAll(targetYear!, '');
  }

  final sortedLocations = List<String>.from(request.locations)
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final loc in sortedLocations) {
    if (remainingQuery.contains(loc)) {
      matchedLocations.add(loc);
      remainingQuery = remainingQuery.replaceAll(loc, '');
    }
  }
  final dedupedLocations = matchedLocations.toSet().toList(growable: false);
  remainingQuery = _stripCreateSemanticStopWords(remainingQuery);

  final candidateIds = <int>[];
  for (final record in request.records) {
    if (record.isProbablyScreenshot) {
      continue;
    }
    if (targetYear != null) {
      final year = DateTime.fromMillisecondsSinceEpoch(
        record.timestamp,
      ).year.toString();
      if (year != targetYear) {
        continue;
      }
    }
    if (dedupedLocations.isNotEmpty &&
        !dedupedLocations.any(record.locationText.contains)) {
      continue;
    }
    candidateIds.add(record.photoId);
  }

  return _CreateSearchFilterResult(
    candidateIds: candidateIds,
    remainingQuery: remainingQuery,
    matchedLocations: dedupedLocations,
    targetYear: targetYear,
  );
}

String _stripCreateSemanticStopWords(String value) {
  var cleaned = value;
  for (final stopWord in _createSemanticStopWords) {
    cleaned = cleaned.replaceAll(stopWord, '');
  }
  cleaned = cleaned.replaceAll(RegExp(r'[的在]'), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

_CreateSemanticScoringResult _scoreCreateSemanticCandidates(
  _CreateSemanticScoringRequest request,
) {
  final scored = <MapEntry<_CreateSemanticScoringInput, double>>[];
  for (final input in request.inputs) {
    if (input.imageEmbedding.length != request.textVector.length ||
        input.imageEmbedding.isEmpty) {
      continue;
    }
    final score = _createCosineSimilarity(
      request.textVector,
      input.imageEmbedding,
    );
    scored.add(
      MapEntry(
        input,
        _boostCreateSemanticScore(
          tags: input.tags,
          query: request.query,
          taxonomyLabel: request.taxonomyLabel,
          semanticScore: score,
        ),
      ),
    );
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  final filtered = scored
      .where((entry) => entry.value >= request.minSimilarity)
      .take(request.maxResults)
      .toList(growable: false);
  final matchedIds = _rankCreateFilteredMatches(
    filtered: filtered,
    taxonomyLabel: request.taxonomyLabel,
    strictTaxonomyThreshold: request.strictTaxonomyThreshold,
  );
  final preview = scored
      .take(5)
      .map((entry) => '${entry.value.toStringAsFixed(4)}#${entry.key.photoId}')
      .join(', ');
  return _CreateSemanticScoringResult(
    matchedIds: matchedIds,
    preview: preview,
    filteredCount: filtered.length,
    scoredCount: scored.length,
  );
}

List<int> _fallbackCreateSearchByVisualTags(
  _CreateVisualTagFallbackRequest request,
) {
  final query = request.query.trim();
  final ids = <int>[];
  for (final record in request.records) {
    if (request.taxonomyLabel != null &&
        record.tags.contains(request.taxonomyLabel)) {
      ids.add(record.photoId);
    } else if (query.length >= 2 && record.tags.contains(query)) {
      ids.add(record.photoId);
    }
    if (ids.length >= request.maxResults) {
      break;
    }
  }
  return ids;
}

double _boostCreateSemanticScore({
  required List<String> tags,
  required String query,
  required String? taxonomyLabel,
  required double semanticScore,
}) {
  var boosted = semanticScore;
  if (taxonomyLabel != null && tags.contains(taxonomyLabel)) {
    boosted += 0.10;
  } else if (query.trim().length >= 2 && tags.contains(query.trim())) {
    boosted += 0.05;
  }
  return boosted;
}

List<int> _rankCreateFilteredMatches({
  required List<MapEntry<_CreateSemanticScoringInput, double>> filtered,
  required String? taxonomyLabel,
  required double strictTaxonomyThreshold,
}) {
  if (filtered.isEmpty) {
    return <int>[];
  }
  if (taxonomyLabel == null) {
    return filtered.map((entry) => entry.key.photoId).toList(growable: false);
  }

  final exactTagMatches = <int>[];
  final semanticOnlyMatches = <int>[];
  for (final entry in filtered) {
    if (entry.key.tags.contains(taxonomyLabel)) {
      exactTagMatches.add(entry.key.photoId);
      continue;
    }
    if (entry.value >= strictTaxonomyThreshold) {
      semanticOnlyMatches.add(entry.key.photoId);
    }
  }
  final merged = <int>[...exactTagMatches, ...semanticOnlyMatches];
  return merged.isNotEmpty
      ? merged
      : filtered.map((entry) => entry.key.photoId).toList(growable: false);
}

double _createCosineSimilarity(List<double> a, List<double> b) {
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final av = a[i];
    final bv = b[i];
    dot += av * bv;
    normA += av * av;
    normB += bv * bv;
  }
  if (normA <= 0 || normB <= 0) {
    return 0.0;
  }
  final similarity = dot / (math.sqrt(normA) * math.sqrt(normB));
  return similarity.isFinite ? similarity : 0.0;
}

_CreateLaunchResult _buildCreateLaunchResult(_CreateLaunchRequest request) {
  final photos = request.records
      .map(
        (record) => Photo(
          id: record.assetId,
          location: record.location,
          path: record.path,
          dateTaken: DateTime.fromMillisecondsSinceEpoch(record.timestamp),
          tags: record.tags,
          caption: record.caption,
          ocrSummary: record.ocrSummary,
          ocrTags: record.ocrTags,
          isSelected: true,
          mediaKind: record.mediaKind,
          thumbnailBytes: record.thumbnailBytes,
        ),
      )
      .toList(growable: false);
  final sortedDates = photos.map((photo) => photo.dateTaken).toList()..sort();
  final now = DateTime.now();
  return _CreateLaunchResult(
    photos: photos,
    startDate: sortedDates.isEmpty ? now : sortedDates.first,
    endDate: sortedDates.isEmpty ? now : sortedDates.last,
  );
}

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final TextEditingController _searchController = TextEditingController();
  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final MobileClipEmbeddingService _mobileClipEmbeddingService =
      MobileClipEmbeddingService();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  bool _isSearching = false;
  static const double _minSemanticSimilarity = 0.18;
  static const int _maxSemanticResults = 300;
  static const double _strictTaxonomySemanticThreshold = 0.22;

  // 搜索结果
  List<PhotoEntity> _searchResults = [];
  // 用户勾选的照片集合（存 ID）
  final Set<int> _selectedPhotoIds = {};
  List<PhotoEntity>? _cachedAnalyzedPhotos;
  List<_CreatePhotoSearchRecord>? _cachedSearchRecords;
  Set<String>? _cachedLocations;

  List<String> get _candidateLabels {
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      return memoriaMasterLabels.take(6).toList(growable: false);
    }

    final normalizedInput = input.toLowerCase();
    final matched = memoriaMasterLabels
        .where(
          (label) =>
              label.toLowerCase().contains(normalizedInput) ||
              normalizedInput.contains(label.toLowerCase()),
        )
        .toList(growable: false);

    if (matched.isNotEmpty) {
      return matched.take(6).toList(growable: false);
    }

    return memoriaMasterLabels.take(6).toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void _resetSearchState() {
    setState(() {
      _isSearching = false;
      _searchResults = <PhotoEntity>[];
      _selectedPhotoIds.clear();
    });
  }

  Future<List<PhotoEntity>> _loadAnalyzedPhotos() async {
    if (_cachedAnalyzedPhotos != null &&
        _cachedSearchRecords != null &&
        _cachedLocations != null) {
      return _cachedAnalyzedPhotos!;
    }

    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final query = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();

    _cachedAnalyzedPhotos = photos;
    _cachedSearchRecords = photos
        .map(_CreatePhotoSearchRecord.fromEntity)
        .toList(growable: false);
    _cachedLocations = await compute(
      _buildCreateLocationDictionary,
      _cachedSearchRecords!,
    );
    return photos;
  }

  // 🧠 语义检索版：本地实体截流 (时间/地点) + Text Embedding 余弦排序
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      _resetSearchState();
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = <PhotoEntity>[];
      _selectedPhotoIds.clear();
    });

    final allAnalyzedPhotos = await _loadAnalyzedPhotos();

    if (allAnalyzedPhotos.isEmpty) {
      _resetSearchState();
      return;
    }

    final allLocations = _cachedLocations ?? const <String>{};
    final searchRecords =
        _cachedSearchRecords ?? const <_CreatePhotoSearchRecord>[];
    final photosById = <int, PhotoEntity>{
      for (final photo in allAnalyzedPhotos) photo.id: photo,
    };

    // ==========================================
    // 💡 阶段二：本地命名实体识别 (NER)
    // ==========================================
    final filterResult = await compute(
      _filterCreateSearchCandidates,
      _CreateSearchFilterRequest(
        query: query,
        locations: allLocations.toList(growable: false),
        records: searchRecords,
      ),
    );

    _logDebug(
      "🔍 [意图分析] 提取年份: ${filterResult.targetYear ?? '无'}, 提取地点: ${filterResult.matchedLocations}, 剩余需AI解析的语义词: '${filterResult.remainingQuery.isEmpty ? '无' : filterResult.remainingQuery}'",
    );

    // ==========================================
    // 💡 阶段三：先做时空过滤，缩小候选集合
    // ==========================================
    final candidates = filterResult.candidateIds
        .map((id) => photosById[id])
        .whereType<PhotoEntity>()
        .toList(growable: false);

    if (candidates.isEmpty) {
      _logDebug('🎯 [综合过滤] 时空过滤后候选为 0');
      if (mounted) {
        setState(() {
          _searchResults = <PhotoEntity>[];
          _isSearching = false;
        });
      }
      return;
    }

    // ==========================================
    // 💡 阶段四：文本向量检索（语义排序）
    // ==========================================
    final semanticQuery = filterResult.remainingQuery.isNotEmpty
        ? filterResult.remainingQuery
        : query.trim();
    final semanticPrompt = _resolveSemanticPrompt(semanticQuery);
    final taxonomyLabel = _resolveTaxonomyLabel(query.trim());
    List<PhotoEntity> matchedPhotos;

    // 纯时空查询：直接返回候选集合（已是时间倒序）
    if (semanticQuery.replaceAll(RegExp(r'\s+'), '').isEmpty) {
      matchedPhotos = List<PhotoEntity>.from(candidates);
    } else {
      try {
        await _semanticService.warmUp();
        final activeModelVersion = await _mobileClipEmbeddingService
            .getSelectedModelVersion();
        final textVector = await _semanticService.embedText(semanticPrompt);

        final scoringInputs = <_CreateSemanticScoringInput>[];
        for (final photo in candidates) {
          final imageEmbedding = _photoEmbeddingIndexRepository
              .readEmbeddingForPhoto(photo, modelVersion: activeModelVersion);
          if (imageEmbedding == null || imageEmbedding.isEmpty) {
            continue;
          }
          if (imageEmbedding.length != textVector.length) {
            continue;
          }
          scoringInputs.add(
            _CreateSemanticScoringInput(
              photoId: photo.id,
              tags: TagSanitizer.sanitizeVisualTags(
                photo.aiTags ?? const <String>[],
              ),
              imageEmbedding: imageEmbedding,
            ),
          );
        }

        if (scoringInputs.isEmpty) {
          _logDebug('⚠️ [语义检索] 候选集中没有可用图像向量，返回 0 条');
          final fallbackIds = await compute(
            _fallbackCreateSearchByVisualTags,
            _CreateVisualTagFallbackRequest(
              records: _recordsForCandidates(candidates),
              query: semanticQuery,
              taxonomyLabel: taxonomyLabel,
              maxResults: _maxSemanticResults,
            ),
          );
          matchedPhotos = _photosForIds(fallbackIds, photosById);
        } else {
          final scoreResult = await compute(
            _scoreCreateSemanticCandidates,
            _CreateSemanticScoringRequest(
              inputs: scoringInputs,
              textVector: textVector,
              query: semanticQuery,
              taxonomyLabel: taxonomyLabel,
              minSimilarity: _minSemanticSimilarity,
              strictTaxonomyThreshold: _strictTaxonomySemanticThreshold,
              maxResults: _maxSemanticResults,
            ),
          );
          matchedPhotos = _photosForIds(scoreResult.matchedIds, photosById);

          if (scoreResult.filteredCount == 0) {
            final fallbackIds = await compute(
              _fallbackCreateSearchByVisualTags,
              _CreateVisualTagFallbackRequest(
                records: _recordsForCandidates(candidates),
                query: semanticQuery,
                taxonomyLabel: taxonomyLabel,
                maxResults: _maxSemanticResults,
              ),
            );
            matchedPhotos = _photosForIds(fallbackIds, photosById);
            _logDebug(
              '⚠️ [语义检索] 全部低于阈值 $_minSemanticSimilarity，'
              '回退到 AI 标签过滤 ${matchedPhotos.length} 条',
            );
          }

          _logDebug(
            '🧠 [语义检索] raw="$semanticQuery" prompt="$semanticPrompt" '
            'top5=[${scoreResult.preview}] threshold=$_minSemanticSimilarity '
            'filtered=${scoreResult.filteredCount}/${scoreResult.scoredCount}',
          );
        }
      } catch (e) {
        _logDebug('⚠️ 语义检索失败，降级为时空过滤结果: $e');
        matchedPhotos = List<PhotoEntity>.from(candidates);
      }
    }

    _logDebug("🎯 [综合过滤] 最终命中照片数: ${matchedPhotos.length}");

    if (mounted) {
      setState(() {
        _searchResults = matchedPhotos;
        _selectedPhotoIds
          ..clear()
          ..addAll(matchedPhotos.map((photo) => photo.id));
        _isSearching = false;
      });
    }
  }

  String _resolveSemanticPrompt(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final mapped = memoriaMasterTaxonomy[trimmed];
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }

    // 优先匹配推荐词，避免把中文短语直接喂给英文主训练的 Text Encoder。
    for (final entry in memoriaMasterTaxonomy.entries) {
      if (trimmed.contains(entry.key) || entry.key.contains(trimmed)) {
        return entry.value;
      }
    }

    return trimmed;
  }

  String? _resolveTaxonomyLabel(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (memoriaMasterTaxonomy.containsKey(trimmed)) {
      return trimmed;
    }

    for (final label in memoriaMasterTaxonomy.keys) {
      if (trimmed.contains(label) || label.contains(trimmed)) {
        return label;
      }
    }

    return null;
  }

  List<_CreatePhotoSearchRecord> _recordsForCandidates(
    List<PhotoEntity> candidates,
  ) {
    return candidates
        .map(_CreatePhotoSearchRecord.fromEntity)
        .toList(growable: false);
  }

  List<PhotoEntity> _photosForIds(
    List<int> ids,
    Map<int, PhotoEntity> photosById,
  ) {
    return ids
        .map((id) => photosById[id])
        .whereType<PhotoEntity>()
        .toList(growable: false);
  }

  // 👆 勾选/取消勾选照片
  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  // 🌟 新增：全选
  void _selectAll() {
    setState(() {
      _selectedPhotoIds.addAll(_searchResults.map((p) => p.id));
    });
  }

  // 🌟 新增：全不选
  void _deselectAll() {
    setState(() {
      _selectedPhotoIds.clear();
    });
  }

  void _toggleSelectAll() {
    if (_searchResults.isEmpty) {
      return;
    }

    final allSelected = _searchResults.every(
      (photo) => _selectedPhotoIds.contains(photo.id),
    );
    if (allSelected) {
      _deselectAll();
    } else {
      _selectAll();
    }
  }

  void _cancelSelection() {
    _deselectAll();
  }

  // 🚀 生成故事（跳转到配置页）
  Future<void> _generateStory() async {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片哦')));
      return;
    }

    // 获取选中的真实照片实体
    final selectedEntities = _searchResults
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();

    final themeTitle = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : '我的专属回忆';

    final launchResult = await compute(
      _buildCreateLaunchResult,
      _CreateLaunchRequest(
        records: selectedEntities
            .map(_CreateLaunchPhotoRecord.fromEntity)
            .toList(growable: false),
        themeTitle: themeTitle,
      ),
    );

    if (!mounted) {
      return;
    }

    final virtualTheme = AITheme(
      id: 'manual_theme',
      emoji: '✨',
      title: themeTitle,
      subtitle: '自定义回忆',
    );
    final virtualEvent = Event(
      id: '-1',
      title: themeTitle,
      season: '精选',
      year: launchResult.startYear,
      location: '多地精选',
      startDate: launchResult.startDate,
      endDate: launchResult.endDate,
      photos: launchResult.photos,
      aiThemes: [virtualTheme],
    );

    // 🌟 5. 携带合规的虚拟数据，正式起飞前往配置页！
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigPage(
          event: virtualEvent,
          selectedPhotos: virtualEvent.photos,
          selectedTheme: virtualTheme,
          semanticSearchQuery: _searchController.text.trim(),
        ),
      ),
    );
  }

  // ==========================================
  // 🎨 页面主 UI 结构
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // 🌌 1. 极光晕染背景层
          _buildAmbientBackground(),

          // 📜 2. 主体滚动内容层
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部返回按钮
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.black87,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),

                // 搜索完成后的头部信息
                if (!_isSearching && _searchResults.isNotEmpty) _buildHeader(),

                // 全选/全不选操作条
                if (!_isSearching && _searchResults.isNotEmpty)
                  _buildSelectionBar(),

                // 核心：瀑布流/网格照片展示
                Expanded(
                  child: _isSearching
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFD17EAD),
                          ),
                        )
                      : _searchResults.isEmpty
                      ? _buildEmptyState()
                      : _buildPhotoGrid(),
                ),

                // 底部留白，防止网格被底部悬浮搜索框彻底挡住
                // const SizedBox(height: 140),
              ],
            ),
          ),

          // 🔎 3. 底部悬浮巨型搜索框
          Positioned(
            left: 0,
            right: 0,
            bottom: 0, // 距离底部有点呼吸感
            child: _buildBottomSearchBar(),
          ),
        ],
      ),
    );
  }

  // 🌌 极光晕染背景生成器 (终极防黑屏版)
  Widget _buildAmbientBackground() {
    return Container(
      color: const Color(0xFFFAFAFA), // 垫一层底色
      // 🌟 核心修改：使用 ImageFiltered 替代 BackdropFilter
      // 它只模糊内部的两个圆块，绝不干扰页面滑动退出的底层图层！
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              left: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88FFB6C1), // 稍微加深一点粉色，因为 ImageFiltered 效果更纯粹
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x77E0B0FF), // 紫罗兰色
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🏆 顶部 Header：大大的图标 + 搜索结果文案 + 继续按钮
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        children: [
          // 左侧花哨的播放渐变方块
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFA07A), Color(0xFFD17EAD)], // 橙粉渐变
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD17EAD).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(width: 16),
          // 中间文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '搜索完成',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '为您搜集到${_searchResults.length}张相关照片',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          // 右侧“继续”按钮
          ElevatedButton(
            onPressed: _generateStory,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD17EAD), // 粉紫色
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              '继续',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ✨ 全选/全不选操作条
  Widget _buildSelectionBar() {
    final allSelected =
        _searchResults.isNotEmpty &&
        _searchResults.every((photo) => _selectedPhotoIds.contains(photo.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              label: Text(allSelected ? '全不选' : '全选'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD17EAD),
                side: const BorderSide(color: Color(0xFFD17EAD), width: 1.5),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _cancelSelection,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey.shade400, width: 1.2),
                minimumSize: const Size.fromHeight(42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('取消'),
            ),
          ),
        ],
      ),
    );
  }

  // 🖼️ 构建无黑罩的照片网格
  Widget _buildPhotoGrid() {
    return GridView.builder(
      scrollCacheExtent: const ScrollCacheExtent.pixels(700),
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 140, // 👈 留出足够的高度，让最后一行照片能滚上来
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final photo = _searchResults[index];
        final isSelected = _selectedPhotoIds.contains(photo.id);
        final file = File(photo.path);

        return GestureDetector(
          onTap: () => _toggleSelection(photo.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: PathImage(path: file.path, fit: BoxFit.cover),
              ),

              // 2. 右上角的选择指示器 (无黑罩，还原设计图的清爽感)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFD17EAD)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFD17EAD)
                          : Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: [
                      if (!isSelected) // 给白圈加点阴影防止在白背景图片上看不见
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔎 底部巨型悬浮搜索框 (带渐变遮罩)
  Widget _buildBottomSearchBar() {
    return Container(
      // 🌟 1. 外层渐变遮罩：给顶部留出 40 像素的渐变过渡区，其他边距还原原来的位置
      padding: const EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // 顶部完全透明
            const Color(0xFFFAFAFA).withValues(alpha: 0.0),
            // 中间半透明过渡
            const Color(0xFFFAFAFA).withValues(alpha: 0.7),
            // 到底部变成实色 (与你的 Scaffold 背景色一致)
            const Color(0xFFFAFAFA),
          ],
          stops: const [0.0, 0.4, 1.0], // 控制渐变的节奏，让透明部分多一点
        ),
      ),
      // 🌟 2. 里层：真正的白色搜索框 (完全保持你原来的绝美设计)
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFD17EAD).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD17EAD).withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20,
            right: 12,
            top: 12,
            bottom: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 多行输入框
              TextField(
                controller: _searchController,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
                onChanged: (value) {
                  setState(() {});
                  if (value.trim().isEmpty &&
                      (_searchResults.isNotEmpty ||
                          _selectedPhotoIds.isNotEmpty)) {
                    _resetSearchState();
                  }
                },
                decoration: const InputDecoration(
                  hintText: '想看什么？比如 "去年的日本之旅"...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _candidateLabels
                    .map(
                      (label) => ActionChip(
                        label: Text(label),
                        onPressed: () {
                          _searchController.text = label;
                          _searchController.selection =
                              TextSelection.fromPosition(
                                TextPosition(offset: label.length),
                              );
                          FocusScope.of(context).unfocus();
                          _performSearch(label);
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              // 右下角的粉色搜索按钮
              Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus(); // 收起键盘
                    _performSearch(_searchController.text);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD17EAD),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.search, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.travel_explore,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty
                ? '输入主题，AI帮你找出回忆'
                : '没有找到匹配的照片，换个词试试？',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
