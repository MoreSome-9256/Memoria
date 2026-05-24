import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../storage/objectbox/entities/media_asset_entity.dart';
import '../storage/objectbox/media_asset_repository.dart';

class MediaSyncSummary {
  const MediaSyncSummary({
    required this.discovered,
    required this.insertedOrUpdated,
    required this.removed,
    required this.limitedAccess,
  });

  final int discovered;
  final int insertedOrUpdated;
  final int removed;
  final bool limitedAccess;
}

class MediaAssetSyncService {
  MediaAssetSyncService._internal();

  static final MediaAssetSyncService _instance = MediaAssetSyncService._internal();

  factory MediaAssetSyncService() => _instance;

  final MediaAssetRepository _repository = MediaAssetRepository();

  static const int _defaultPageSize = 200;

  Function(MethodCall)? _changeCallback;
  bool _isReconciling = false;

  Future<PermissionState> requestPhotoPermission() {
    return PhotoManager.requestPermissionExtend();
  }

  Future<bool> presentLimitedSelectorIfNeeded() async {
    if (!Platform.isIOS) {
      return false;
    }
    final state = await PhotoManager.requestPermissionExtend();
    if (state != PermissionState.limited) {
      return false;
    }
    await PhotoManager.presentLimited();
    return true;
  }

  Future<MediaSyncSummary> reconcile({
    int pageSize = _defaultPageSize,
  }) async {
    if (_isReconciling) {
      return const MediaSyncSummary(
        discovered: 0,
        insertedOrUpdated: 0,
        removed: 0,
        limitedAccess: false,
      );
    }
    _isReconciling = true;

    try {
      final permission = await requestPhotoPermission();
      if (!permission.isAuth && !permission.hasAccess) {
        throw StateError('没有相册权限，无法扫描资源。');
      }

      final constrainedPageSize = pageSize.clamp(100, 300);
      final albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
      if (albums.isEmpty) {
        return MediaSyncSummary(
          discovered: 0,
          insertedOrUpdated: 0,
          removed: _cleanupMissing(const <String>{}),
          limitedAccess: permission == PermissionState.limited,
        );
      }

      final allAlbum = albums.first;
      final total = await allAlbum.assetCountAsync;
      final discoveredAssetIds = <String>{};
      var insertedOrUpdated = 0;

      for (var offset = 0; offset < total; offset += constrainedPageSize) {
        final end = (offset + constrainedPageSize > total)
            ? total
            : (offset + constrainedPageSize);
        final assets = await allAlbum.getAssetListRange(start: offset, end: end);
        if (assets.isEmpty) {
          continue;
        }
        final ids = assets.map((asset) => asset.id).toList(growable: false);
        final existingMap = _repository.getByAssetIdMap(ids);
        final batch = <MediaAssetEntity>[];

        for (final asset in assets) {
          discoveredAssetIds.add(asset.id);
          final currentHash = _assetHash(asset);
          final existing = existingMap[asset.id];
          if (existing != null && existing.contentHash == currentHash) {
            continue;
          }

          final entity = existing ?? MediaAssetEntity(assetId: asset.id);
          entity.width = asset.width;
          entity.height = asset.height;
          entity.createTimeMs =
              asset.createDateTime.millisecondsSinceEpoch;
          entity.modifiedTimeMs =
              asset.modifiedDateTime.millisecondsSinceEpoch;
          entity.durationMs = asset.duration * 1000;
          entity.subtype = asset.subtype;
          entity.contentHash = currentHash;
          entity.errorMessage = null;
          entity.embedding = null;
          entity.modelVersion = null;
          entity.embeddingUpdatedAtMs = null;
          entity.setStatus(existing == null
              ? MediaAssetStatus.pending
              : MediaAssetStatus.dirty);
          batch.add(entity);
        }

        _repository.putMany(batch);
        insertedOrUpdated += batch.length;
      }

      final removed = _cleanupMissing(discoveredAssetIds);
      return MediaSyncSummary(
        discovered: discoveredAssetIds.length,
        insertedOrUpdated: insertedOrUpdated,
        removed: removed,
        limitedAccess: permission == PermissionState.limited,
      );
    } finally {
      _isReconciling = false;
    }
  }

  Future<void> startChangeNotify() async {
    if (_changeCallback != null) {
      return;
    }

    await PhotoManager.startChangeNotify();
    _changeCallback = (MethodCall _) async {
      // Small debounce window to coalesce bursty change notifications.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        await reconcile();
      } catch (error) {
        debugPrint('Media reconcile after change failed: $error');
      }
    };
    PhotoManager.addChangeCallback(_changeCallback!);
  }

  Future<void> stopChangeNotify() async {
    final callback = _changeCallback;
    if (callback != null) {
      PhotoManager.removeChangeCallback(callback);
    }
    _changeCallback = null;
    await PhotoManager.stopChangeNotify();
  }

  int _cleanupMissing(Set<String> scannedAssetIds) {
    final existingIds = _repository.loadAllAssetIds();
    if (existingIds.isEmpty) {
      return 0;
    }
    final removed = existingIds
        .where((id) => !scannedAssetIds.contains(id))
        .toList(growable: false);
    if (removed.isNotEmpty) {
      _repository.removeByAssetIds(removed);
    }
    return removed.length;
  }

  String _assetHash(AssetEntity asset) {
    final payload =
        '${asset.id}|${asset.width}|${asset.height}|${asset.duration}|${asset.modifiedDateTime.millisecondsSinceEpoch}|${asset.typeInt}';
    return sha1.convert(utf8.encode(payload)).toString();
  }
}
