import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../utils/photo_filter_helper.dart';
import 'album_selection_preference_service.dart';
import 'app_ai_settings_service.dart';
import 'junk_photo_filter_service.dart';
import 'media_access_grant_service.dart';

part 'photo_service_models.dart';
part 'photo_service_scan.dart';
part 'photo_service_scan_coordinator.dart';
part 'photo_service_asset_build.dart';
part 'photo_service_asset_builder.dart';
part 'photo_service_access.dart';
part 'photo_service_ai_reset.dart';

class PhotoService {
  bool _isInitialized = false;
  static const int _assetExistenceWorkerCount = 12;
  static const int _assetBuildWorkerCount = 8;
  static const Duration _photoAccessCacheTtl = Duration(seconds: 20);

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  PhotoService._internal();

  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final FaceEmbeddingIndexRepository _faceEmbeddingIndexRepository =
      FaceEmbeddingIndexRepository();
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

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    await getApplicationDocumentsDirectory();
    await ObjectBoxService().init();
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

    debugPrint('🗑️ 已清空缓存数据（照片/事件/故事）');
  }

  Future<_ScanBuildResult> _buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
    bool resolveFile = true,
  }) {
    return _PhotoAssetBuilder(this).buildPhotoEntities(
      assets,
      skipExisting: skipExisting,
      filterProfile: filterProfile,
      resolveFile: resolveFile,
    );
  }

  Future<_SingleAssetBuildResult> _buildSingleAssetPhoto(
    AssetEntity asset, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
    bool resolveFile = false,
  }) {
    return _PhotoAssetBuilder(
      this,
    ).buildSingleAssetPhoto(asset, filterProfile: filterProfile, resolveFile: resolveFile);
  }

  Future<_SingleAssetBuildResult> _buildSingleFilePhoto(
    File file, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) {
    return _PhotoAssetBuilder(
      this,
    ).buildSingleFilePhoto(file, filterProfile: filterProfile);
  }

  Future<_SingleAssetBuildResult> _buildSingleGrantedMediaPhoto(
    AndroidGrantedMediaReference media, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) {
    return _PhotoAssetBuilder(
      this,
    ).buildSingleGrantedMediaPhoto(media, filterProfile: filterProfile);
  }

  Future<File?> _resolveReadableFile(AssetEntity asset) {
    return _PhotoAssetBuilder(this).resolveReadableFile(asset);
  }

  int _resolveBestTimestampMs(AssetEntity asset, File file) {
    return _PhotoAssetBuilder(this).resolveBestTimestampMs(asset, file);
  }
}
