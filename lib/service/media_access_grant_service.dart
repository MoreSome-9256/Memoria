import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_ai_settings_service.dart';

class MediaAccessGrantSnapshot {
  const MediaAccessGrantSnapshot({
    required this.selectedAssetIds,
    required this.selectedFilePaths,
    required this.androidTreeUris,
  });

  final List<String> selectedAssetIds;
  final List<String> selectedFilePaths;
  final List<String> androidTreeUris;

  bool get hasAnyGrant =>
      selectedAssetIds.isNotEmpty ||
      selectedFilePaths.isNotEmpty ||
      androidTreeUris.isNotEmpty;
}

class PickedMediaGrantResult {
  const PickedMediaGrantResult({
    required this.addedAssetIds,
    required this.totalSelectedAssetIds,
  });

  final int addedAssetIds;
  final int totalSelectedAssetIds;
}

class AndroidDirectoryGrantResult {
  const AndroidDirectoryGrantResult({
    required this.uri,
    required this.displayName,
  });

  final String uri;
  final String displayName;
}

class MediaAccessGrantService {
  MediaAccessGrantService._();
  static final MediaAccessGrantService instance = MediaAccessGrantService._();

  static const _channel = MethodChannel('memoria/media_access');
  static const _selectedAssetIdsKey = 'media_access_selected_asset_ids';
  static const _selectedFilePathsKey = 'media_access_selected_file_paths';
  static const _androidTreeUrisKey = 'media_access_android_tree_uris';
  final ImagePicker _picker = ImagePicker();

  Future<MediaAccessGrantSnapshot> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return MediaAccessGrantSnapshot(
      selectedAssetIds:
          prefs.getStringList(_selectedAssetIdsKey) ?? const <String>[],
      selectedFilePaths:
          prefs.getStringList(_selectedFilePathsKey) ?? const <String>[],
      androidTreeUris:
          prefs.getStringList(_androidTreeUrisKey) ?? const <String>[],
    );
  }

  Future<PickedMediaGrantResult> pickMedia() async {
    final settings = await AppAiSettingsService.instance.load();
    final picked = settings.includeVideos
        ? await _picker.pickMultipleMedia()
        : await _picker.pickMultiImage();
    if (picked.isEmpty) {
      return const PickedMediaGrantResult(
        addedAssetIds: 0,
        totalSelectedAssetIds: 0,
      );
    }
    return addSelectedFilePaths(picked.map((file) => file.path));
  }

  Future<void> presentLimitedLibraryPicker() async {
    await PhotoManager.presentLimited();
  }

  Future<PickedMediaGrantResult> addSelectedAssetIds(
    Iterable<String> assetIds,
  ) async {
    final normalized = assetIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_selectedAssetIdsKey) ?? <String>[];
    final merged = <String>{...existing, ...normalized}.toList(growable: false);
    await prefs.setStringList(_selectedAssetIdsKey, merged);
    return PickedMediaGrantResult(
      addedAssetIds: merged.length - existing.toSet().length,
      totalSelectedAssetIds: merged.length,
    );
  }

  Future<PickedMediaGrantResult> addSelectedFilePaths(
    Iterable<String> paths,
  ) async {
    final normalized = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet();
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_selectedFilePathsKey) ?? <String>[];
    final merged = <String>{...existing, ...normalized}.toList(growable: false);
    await prefs.setStringList(_selectedFilePathsKey, merged);
    return PickedMediaGrantResult(
      addedAssetIds: merged.length - existing.toSet().length,
      totalSelectedAssetIds: merged.length,
    );
  }

  Future<void> clearSelectedAssets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedAssetIdsKey);
    await prefs.remove(_selectedFilePathsKey);
  }

  Future<AndroidDirectoryGrantResult?> requestAndroidDirectoryGrant() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'requestDirectoryGrant',
    );
    if (result == null) {
      return null;
    }
    final uri = result['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return null;
    }
    final displayName = result['displayName'] as String? ?? uri;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_androidTreeUrisKey) ?? <String>[];
    if (!existing.contains(uri)) {
      await prefs.setStringList(_androidTreeUrisKey, <String>[
        ...existing,
        uri,
      ]);
    }
    return AndroidDirectoryGrantResult(uri: uri, displayName: displayName);
  }

  Future<void> removeAndroidDirectoryGrant(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_androidTreeUrisKey) ?? <String>[];
    await prefs.setStringList(
      _androidTreeUrisKey,
      existing.where((value) => value != uri).toList(growable: false),
    );
    if (Platform.isAndroid) {
      unawaited(_channel.invokeMethod<void>('releaseDirectoryGrant', uri));
    }
  }

  Future<void> requestBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }
}
