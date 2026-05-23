import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SystemPhotoAccessService {
  SystemPhotoAccessService._internal();

  static final SystemPhotoAccessService _instance =
      SystemPhotoAccessService._internal();
  factory SystemPhotoAccessService() => _instance;

  static const String _persistentUrisKey = 'persistent_content_uris';

  Future<bool> requestScopedAccess() async {
    if (!Platform.isAndroid) return false;
    if (await _hasScopedAccess()) return true;

    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (permission == PermissionState.authorized ||
          permission == PermissionState.limited) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Scoped access request failed: $e');
      return false;
    }
  }

  Future<bool> _hasScopedAccess() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      return permission == PermissionState.authorized ||
          permission == PermissionState.limited;
    } catch (_) {
      return false;
    }
  }

  Future<List<AssetEntity>> pickImagesFromSystem({
    int maxCount = 0,
  }) async {
    try {
      if (Platform.isAndroid) {
        final permission = await Permission.photos.status;
        if (!permission.isGranted && !permission.isLimited) {
          final result = await Permission.photos.request();
          if (!result.isGranted && !result.isLimited) {
            return [];
          }
        }
      }

      final permissionState = await PhotoManager.requestPermissionExtend();
      if (permissionState != PermissionState.authorized &&
          permissionState != PermissionState.limited) {
        return [];
      }

      final recent = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (recent.isEmpty) return [];
      final entities = await recent.first.getAssetListRange(
        start: 0,
        end: maxCount > 0 ? maxCount : 20,
      );
      return entities;
    } catch (e) {
      debugPrint('Image picker failed: $e');
      return [];
    }
  }

  Future<void> savePersistentUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final uris = prefs.getStringList(_persistentUrisKey) ?? [];
    if (!uris.contains(uri)) {
      uris.add(uri);
      await prefs.setStringList(_persistentUrisKey, uris);
    }
  }

  Future<List<String>> getPersistentUris() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_persistentUrisKey) ?? [];
  }

  Future<void> removePersistentUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final uris = prefs.getStringList(_persistentUrisKey) ?? [];
    uris.remove(uri);
    await prefs.setStringList(_persistentUrisKey, uris);
  }

  Future<void> clearPersistentUris() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_persistentUrisKey);
  }

  Future<void> addAlbumToWhitelist(String albumId, String albumName) async {
    final prefs = await SharedPreferences.getInstance();
    final currentIds = prefs.getStringList('whitelist_album_ids') ?? [];
    final currentNames = prefs.getStringList('whitelist_album_names') ?? [];
    if (!currentIds.contains(albumId)) {
      currentIds.add(albumId);
      currentNames.add(albumName);
      await prefs.setStringList('whitelist_album_ids', currentIds);
      await prefs.setStringList('whitelist_album_names', currentNames);
    }
  }

  Future<void> removeAlbumFromWhitelist(String albumId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentIds = prefs.getStringList('whitelist_album_ids') ?? [];
    final currentNames = prefs.getStringList('whitelist_album_names') ?? [];
    final idx = currentIds.indexOf(albumId);
    if (idx >= 0) {
      currentIds.removeAt(idx);
      if (idx < currentNames.length) currentNames.removeAt(idx);
      await prefs.setStringList('whitelist_album_ids', currentIds);
      await prefs.setStringList('whitelist_album_names', currentNames);
    }
  }

  Future<List<Map<String, String>>> getWhitelistedAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('whitelist_album_ids') ?? [];
    final names = prefs.getStringList('whitelist_album_names') ?? [];
    final result = <Map<String, String>>[];
    for (var i = 0; i < ids.length; i++) {
      result.add({
        'id': ids[i],
        'name': i < names.length ? names[i] : ids[i],
      });
    }
    return result;
  }

  Future<bool> hasWhitelistedAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('whitelist_album_ids');
    return ids != null && ids.isNotEmpty;
  }
}
