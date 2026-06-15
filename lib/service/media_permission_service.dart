import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaPermissionSnapshot {
  const MediaPermissionSnapshot(this.state);

  final PermissionState state;

  bool get hasAccess => state.hasAccess;
  bool get isLimited => state.isLimited;
  bool get isAuthorized => state.isAuth;
}

class MediaPermissionService {
  MediaPermissionService._();

  static const _snapshotKey = 'media_permission_snapshot_v1';

  /// Memoria only reads visual media. RequestType.all also includes audio on
  /// Android and can downgrade an otherwise valid visual-media grant.
  static const requestOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  /// The app album whitelist is a second boundary on top of OS access.
  ///
  /// Limited-library access is already an asset-level boundary, so album
  /// membership is not reliable enough to narrow it again. Keep the saved
  /// whitelist intact and resume it automatically after full access returns.
  static Set<String> effectiveAlbumWhitelist({
    required PermissionState state,
    required Iterable<String> savedAlbumIds,
  }) {
    return state.isLimited ? <String>{} : savedAlbumIds.toSet();
  }

  /// Reads the OS state from the UI isolate and persists it for foreground
  /// workers. If the plugin cannot read state, use the last known snapshot.
  static Future<PermissionState> readPermissionState() async {
    try {
      return await readLivePermissionState();
    } catch (error) {
      debugPrint(
        '[media-permission] state read failed, using snapshot: $error',
      );
      return (await readCachedSnapshot()).state;
    }
  }

  /// Reads the current OS state and never trusts a cached grant. Use before
  /// starting work or making destructive decisions.
  static Future<PermissionState> readLivePermissionState() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: requestOption,
    );
    await persistState(state);
    return state;
  }

  static Future<bool> canDeleteUnavailableMedia() async {
    try {
      final state = await readLivePermissionState();
      return state.isAuth && !state.isLimited;
    } catch (error) {
      debugPrint(
        '[media-permission] skip destructive cleanup; live state unavailable: '
        '$error',
      );
      return false;
    }
  }

  /// Must only be called from an explicit user action in the UI isolate.
  static Future<PermissionState> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: requestOption,
    );
    await persistState(state);
    return state;
  }

  /// Safe for foreground/background isolates. Never invokes photo_manager.
  static Future<MediaPermissionSnapshot> readCachedSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_snapshotKey);
    final state = PermissionState.values
        .where((item) => item.name == raw)
        .firstOrNull;
    return MediaPermissionSnapshot(state ?? PermissionState.notDetermined);
  }

  static Future<void> persistState(PermissionState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, state.name);
  }

  static Future<void> openSystemSettings() => PhotoManager.openSetting();

  /// Opens the Android 14/iOS limited-library selector. Call from a user tap.
  static Future<PermissionState> selectMorePhotos() async {
    await PhotoManager.presentLimited(type: RequestType.common);
    return readPermissionState();
  }
}
