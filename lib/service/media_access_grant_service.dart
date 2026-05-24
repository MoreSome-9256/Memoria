import 'dart:async';
import 'dart:convert';
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
    required this.androidTreeDisplayNames,
    required this.includedSubpathsBySource,
    required this.excludedSubpathsBySource,
    required this.disabledAutoSourceIds,
    required this.sourcesWithoutChildren,
    required this.excludeScreenshots,
    required this.excludeScreenRecordings,
    required this.excludeSmallMedia,
    required this.excludeDuplicates,
    required this.excludedMediaTypes,
  });

  final List<String> selectedAssetIds;
  final List<String> selectedFilePaths;
  final List<String> androidTreeUris;
  final Map<String, String> androidTreeDisplayNames;
  final Map<String, List<String>> includedSubpathsBySource;
  final Map<String, List<String>> excludedSubpathsBySource;
  final List<String> disabledAutoSourceIds;
  final List<String> sourcesWithoutChildren;
  final bool excludeScreenshots;
  final bool excludeScreenRecordings;
  final bool excludeSmallMedia;
  final bool excludeDuplicates;
  final List<String> excludedMediaTypes;

  bool get hasAnyGrant =>
      selectedAssetIds.isNotEmpty ||
      selectedFilePaths.isNotEmpty ||
      androidTreeUris.isNotEmpty;

  int get manualMediaCount =>
      selectedAssetIds.length + selectedFilePaths.length;

  bool isAutoSourceEnabled(String sourceId) =>
      !disabledAutoSourceIds.contains(sourceId);

  bool includesChildren(String sourceId) =>
      !sourcesWithoutChildren.contains(sourceId);

  int includedSubpathCount(String sourceId) =>
      includedSubpathsBySource[sourceId]?.length ?? 0;

  int excludedSubpathCount(String sourceId) =>
      excludedSubpathsBySource[sourceId]?.length ?? 0;

  String displayNameForSource(String sourceId) =>
      androidTreeDisplayNames[sourceId] ?? sourceId;
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
  static const _androidTreeDisplayNamesKey =
      'media_access_android_tree_display_names';
  static const _includedSubpathsKey = 'media_access_included_subpaths';
  static const _excludedSubpathsKey = 'media_access_excluded_subpaths';
  static const _disabledAutoSourceIdsKey =
      'media_access_disabled_auto_source_ids';
  static const _sourcesWithoutChildrenKey =
      'media_access_sources_without_children';
  static const _excludeScreenshotsKey = 'media_access_exclude_screenshots';
  static const _excludeScreenRecordingsKey =
      'media_access_exclude_screen_recordings';
  static const _excludeSmallMediaKey = 'media_access_exclude_small_media';
  static const _excludeDuplicatesKey = 'media_access_exclude_duplicates';
  static const _excludedMediaTypesKey = 'media_access_excluded_media_types';
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
      androidTreeDisplayNames: _decodeStringMap(
        prefs.getString(_androidTreeDisplayNamesKey),
      ),
      includedSubpathsBySource: _decodeStringListMap(
        prefs.getString(_includedSubpathsKey),
      ),
      excludedSubpathsBySource: _decodeStringListMap(
        prefs.getString(_excludedSubpathsKey),
      ),
      disabledAutoSourceIds:
          prefs.getStringList(_disabledAutoSourceIdsKey) ?? const <String>[],
      sourcesWithoutChildren:
          prefs.getStringList(_sourcesWithoutChildrenKey) ?? const <String>[],
      excludeScreenshots: prefs.getBool(_excludeScreenshotsKey) ?? true,
      excludeScreenRecordings:
          prefs.getBool(_excludeScreenRecordingsKey) ?? true,
      excludeSmallMedia: prefs.getBool(_excludeSmallMediaKey) ?? true,
      excludeDuplicates: prefs.getBool(_excludeDuplicatesKey) ?? true,
      excludedMediaTypes:
          prefs.getStringList(_excludedMediaTypesKey) ?? const <String>[],
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
    final displayNames = _decodeStringMap(
      prefs.getString(_androidTreeDisplayNamesKey),
    );
    displayNames[uri] = displayName;
    await prefs.setString(
      _androidTreeDisplayNamesKey,
      jsonEncode(displayNames),
    );
    return AndroidDirectoryGrantResult(uri: uri, displayName: displayName);
  }

  Future<void> removeAndroidDirectoryGrant(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_androidTreeUrisKey) ?? <String>[];
    await prefs.setStringList(
      _androidTreeUrisKey,
      existing.where((value) => value != uri).toList(growable: false),
    );
    final displayNames = _decodeStringMap(
      prefs.getString(_androidTreeDisplayNamesKey),
    )..remove(uri);
    await prefs.setString(
      _androidTreeDisplayNamesKey,
      jsonEncode(displayNames),
    );
    final excluded = _decodeStringListMap(prefs.getString(_excludedSubpathsKey))
      ..remove(uri);
    await prefs.setString(_excludedSubpathsKey, jsonEncode(excluded));
    final included = _decodeStringListMap(prefs.getString(_includedSubpathsKey))
      ..remove(uri);
    await prefs.setString(_includedSubpathsKey, jsonEncode(included));
    await _removeFromStringListPref(prefs, _disabledAutoSourceIdsKey, uri);
    await _removeFromStringListPref(prefs, _sourcesWithoutChildrenKey, uri);
    if (Platform.isAndroid) {
      unawaited(_channel.invokeMethod<void>('releaseDirectoryGrant', uri));
    }
  }

  Future<void> setAutoSourceEnabled(String sourceId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        prefs.getStringList(_disabledAutoSourceIdsKey) ?? <String>[];
    final next = <String>{...existing};
    enabled ? next.remove(sourceId) : next.add(sourceId);
    await prefs.setStringList(
      _disabledAutoSourceIdsKey,
      next.toList(growable: false)..sort(),
    );
  }

  Future<void> setSourceIncludesChildren(
    String sourceId,
    bool includesChildren,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        prefs.getStringList(_sourcesWithoutChildrenKey) ?? <String>[];
    final next = <String>{...existing};
    includesChildren ? next.remove(sourceId) : next.add(sourceId);
    await prefs.setStringList(
      _sourcesWithoutChildrenKey,
      next.toList(growable: false)..sort(),
    );
  }

  Future<void> setIncludedSubpaths(
    String sourceId,
    Iterable<String> subpaths,
  ) async {
    final normalized =
        subpaths
            .map((subpath) => subpath.trim())
            .where((subpath) => subpath.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final prefs = await SharedPreferences.getInstance();
    final included = _decodeStringListMap(
      prefs.getString(_includedSubpathsKey),
    );
    if (normalized.isEmpty) {
      included.remove(sourceId);
    } else {
      included[sourceId] = normalized;
    }
    await prefs.setString(_includedSubpathsKey, jsonEncode(included));
  }

  Future<void> addExcludedSubpath(String sourceId, String subpath) async {
    final normalized = subpath.trim();
    if (normalized.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final excluded = _decodeStringListMap(
      prefs.getString(_excludedSubpathsKey),
    );
    final existing = excluded[sourceId] ?? const <String>[];
    final values = <String>{...existing, normalized}.toList(growable: false)
      ..sort();
    excluded[sourceId] = values;
    await prefs.setString(_excludedSubpathsKey, jsonEncode(excluded));
  }

  Future<void> removeExcludedSubpath(String sourceId, String subpath) async {
    final prefs = await SharedPreferences.getInstance();
    final excluded = _decodeStringListMap(
      prefs.getString(_excludedSubpathsKey),
    );
    final values = excluded[sourceId]
        ?.where((value) => value != subpath)
        .toList(growable: false);
    if (values == null || values.isEmpty) {
      excluded.remove(sourceId);
    } else {
      excluded[sourceId] = values;
    }
    await prefs.setString(_excludedSubpathsKey, jsonEncode(excluded));
  }

  Future<void> setDefaultExclusionRules({
    required bool excludeScreenshots,
    required bool excludeScreenRecordings,
    required bool excludeSmallMedia,
    required bool excludeDuplicates,
    required List<String> excludedMediaTypes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_excludeScreenshotsKey, excludeScreenshots);
    await prefs.setBool(_excludeScreenRecordingsKey, excludeScreenRecordings);
    await prefs.setBool(_excludeSmallMediaKey, excludeSmallMedia);
    await prefs.setBool(_excludeDuplicatesKey, excludeDuplicates);
    await prefs.setStringList(_excludedMediaTypesKey, excludedMediaTypes);
  }

  Future<void> requestBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  Future<void> _removeFromStringListPref(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    final existing = prefs.getStringList(key) ?? <String>[];
    await prefs.setStringList(
      key,
      existing.where((item) => item != value).toList(growable: false),
    );
  }

  Map<String, String> _decodeStringMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return <String, String>{};
  }

  Map<String, List<String>> _decodeStringListMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, List<String>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) {
          final list = value is List
              ? value.map((item) => item.toString()).toList(growable: false)
              : const <String>[];
          return MapEntry(key.toString(), list);
        });
      }
    } catch (_) {}
    return <String, List<String>>{};
  }
}
