import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/create_recommendation_entity.dart';
import '../models/entity/digital_album_book_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/story_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/objectbox/media_asset_repository.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../utils/photo_filter_helper.dart';
import '../utils/media_type_helper.dart';
import 'album_selection_preference_service.dart';
import 'app_ai_settings_service.dart';
import 'junk_photo_filter_service.dart';
import 'media_permission_service.dart';
import 'media_thumbnail_cache_service.dart';
import 'mobileclip_tag_service.dart';
import 'semantic_matching_service.dart';

part 'photo_service_models.dart';
part 'photo_service_scan.dart';
part 'photo_service_scan_coordinator.dart';
part 'photo_service_asset_build.dart';
part 'photo_service_asset_builder.dart';
part 'photo_service_access.dart';
part 'photo_service_ai_reset.dart';

class PhotoService {
  bool _isInitialized = false;
  static const Duration _photoAccessCacheTtl = Duration(seconds: 20);

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final FaceEmbeddingIndexRepository _faceEmbeddingIndexRepository =
      FaceEmbeddingIndexRepository();
  final MediaAssetRepository _mediaAssetRepository = MediaAssetRepository();
  final Map<String, _PhotoAccessCacheEntry> _photoAccessCache =
      <String, _PhotoAccessCacheEntry>{};

  Store get _store => ObjectBoxService().store;
  Box<PhotoEntity> get _photoBox => _store.box<PhotoEntity>();
  Box<FaceEntity> get _faceBox => _store.box<FaceEntity>();
  Box<EventEntity> get _eventBox => _store.box<EventEntity>();
  Box<StoryEntity> get _storyBox => _store.box<StoryEntity>();
  Box<DigitalAlbumBookEntity> get _albumBookBox =>
      _store.box<DigitalAlbumBookEntity>();
  Box<CreateRecommendationEntity> get _recommendationBox =>
      _store.box<CreateRecommendationEntity>();

  Store get store => _store;
  int get totalPhotoCount => _photoBox.count();

  Future<void> init() async {
    if (_isInitialized && ObjectBoxService().isInitialized) {
      return;
    }
    await getApplicationDocumentsDirectory();
    await ObjectBoxService().ensureInitialized();
    _isInitialized = true;
  }

  Future<void> clearAllCachedData() async {
    _store.runInTransaction(TxMode.write, () {
      _albumBookBox.removeAll();
      _recommendationBox.removeAll();
      _storyBox.removeAll();
      _eventBox.removeAll();
      _faceBox.removeAll();
      _photoBox.removeAll();
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();
    _mediaAssetRepository.clearAll();

    await MobileClipTagService().dispose();
    await SemanticMatchingService().dispose();

    try {
      final tempDir = await getTemporaryDirectory();
      final tagCacheFile = File('${tempDir.path}/tag_prototype_cache.json');
      if (await tagCacheFile.exists()) {
        await tagCacheFile.delete();
        debugPrint('🗑️ 已删除标签原型缓存文件');
      }
    } catch (e) {
      debugPrint('⚠️ 删除标签原型缓存文件失败: $e');
    }

    debugPrint('🗑️ 已清空缓存数据（照片/事件/故事/向量索引/语义标签）');
  }

  Future<_ScanBuildResult> _buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) {
    return _PhotoAssetBuilder(this).buildPhotoEntities(
      assets,
      skipExisting: skipExisting,
      filterProfile: filterProfile,
    );
  }

  Future<_SingleAssetBuildResult> _buildSingleAssetPhoto(
    AssetEntity asset, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) {
    return _PhotoAssetBuilder(
      this,
    ).buildSingleAssetPhoto(asset, filterProfile: filterProfile);
  }

  Future<PhotoEntity?> buildAndSaveSinglePhoto(
    AssetEntity asset, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) async {
    final existingQuery = _photoBox
        .query(PhotoEntity_.assetId.equals(asset.id))
        .build();
    try {
      final existing = existingQuery.findFirst();
      if (existing != null) {
        final refreshed = await _PhotoAssetBuilder(
          this,
        )._refreshIfChanged(existing, asset);
        if (refreshed != null) {
          _photoBox.put(refreshed);
          return refreshed;
        }
        if (existing.thumbnailBytes == null ||
            existing.thumbnailBytes!.isEmpty) {
          final thumbnailBytes = await MediaThumbnailCacheService.instance
              .generateCompressedBytes(asset);
          if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
            existing.thumbnailBytes = thumbnailBytes;
            _photoBox.put(existing);
          }
        }
        return existing;
      }
    } finally {
      existingQuery.close();
    }

    final result = await _buildSingleAssetPhoto(
      asset,
      filterProfile: filterProfile,
    );
    if (result.photo == null) return null;
    final id = _photoBox.put(result.photo!);
    if (id <= 0) return null;
    result.photo!.id = id;
    return result.photo!;
  }

  void updatePhotoInTransaction(
    int photoId,
    void Function(PhotoEntity?) update,
  ) {
    _store.runInTransaction(TxMode.write, () {
      final p = _photoBox.get(photoId);
      update(p);
      if (p != null) _photoBox.put(p);
    });
  }
}
