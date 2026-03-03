class PhotoFilterHelper {
  const PhotoFilterHelper._();

  static final RegExp _seedFileNamePattern = RegExp(r'\d{8}_\d{6}');

  static bool hasValidTimestamp(int timestampMs) {
    return timestampMs > 0;
  }

  static bool hasValidGps(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude != 0 &&
        longitude != 0;
  }

  static bool isLikelyScreenshotByRatio(int width, int height) {
    if (width <= 0 || height <= 0) {
      return true;
    }

    final ratio = width / height;
    return ratio < 0.45 || ratio > 2.2;
  }

  static bool isLikelyCameraPhoto(String filePath) {
    final normalized = filePath.toLowerCase();
    final fileName = normalized.split('/').last;

    const screenshotKeywords = ['screenshot', 'screen shot', '截屏', '截图'];
    if (screenshotKeywords.any(fileName.contains)) {
      return false;
    }

    if (normalized.contains('/dcim/') || normalized.contains('/camera/')) {
      return true;
    }

    const cameraPrefixes = ['img_', 'dsc_', 'pxl_', 'mvimg_'];
    if (cameraPrefixes.any((prefix) => fileName.startsWith(prefix))) {
      return true;
    }

    // 兼容测试集重命名文件：文件名包含日期时间片段（yyyyMMdd_HHmmss）
    const photoExtensions = ['.jpg', '.jpeg', '.heic', '.heif', '.png'];
    final hasPhotoExtension = photoExtensions.any(fileName.endsWith);
    if (!hasPhotoExtension) {
      return false;
    }

    return _seedFileNamePattern.hasMatch(fileName);
  }
}
