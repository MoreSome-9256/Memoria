import 'package:photo_manager/photo_manager.dart';

class MediaPermissionService {
  MediaPermissionService._();

  static const requestOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.all,
      mediaLocation: false,
    ),
  );

  static Future<PermissionState> readPermissionState() {
    return PhotoManager.getPermissionState(requestOption: requestOption);
  }

  static Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend(requestOption: requestOption);
  }

  static Future<void> openSystemSettings() => PhotoManager.openSetting();

  static Future<void> selectMorePhotos() {
    return PhotoManager.presentLimited(type: RequestType.all);
  }
}
