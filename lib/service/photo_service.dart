/// 照片主服务，集中管理相册访问、缓存、实体转换和同步流程。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/entity/create_recommendation_entity.dart';
import '../models/entity/face_entity.dart';
import '../models/entity/digital_album_book_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/story_entity.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../data/tag_taxonomy_v2.dart';
import '../service/junk_photo_filter_service.dart';
import '../utils/photo_filter_helper.dart';
import '../models/chat_message.dart'; 

part 'photo_service_models.dart';
part 'photo_service_scan.dart';
part 'photo_service_scan_coordinator.dart';
part 'photo_service_asset_build.dart';
part 'photo_service_asset_builder.dart';
part 'photo_service_access.dart';
part 'photo_service_ai_reset.dart';

class PhotoService {
  late Isar _isar;
  bool _isInitialized = false;
  static const bool _verboseAssetLogging = false;
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

  Isar get isar => _isar;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        PhotoEntitySchema,
        FaceEntitySchema,
        EventEntitySchema,
        StoryEntitySchema,
        ChatMessageSchema,
        CreateRecommendationEntitySchema,
        DigitalAlbumBookEntitySchema,
      ], // 注册所有实体
      directory: dir.path,
    );
    _isInitialized = true;
  }

  Future<void> clearAllCachedData() async {
    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().clear();
      await _isar.collection<CreateRecommendationEntity>().clear();
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint("🗑️ 已清空 Isar 缓存数据（照片/事件/故事）");
  }
}
