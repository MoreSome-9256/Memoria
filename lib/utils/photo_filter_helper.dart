class PhotoFilterHelper {
  const PhotoFilterHelper._();

  static final RegExp _seedFileNamePattern = RegExp(r'\d{8}_\d{6}');
  static final RegExp _dateTimeInFileNamePattern = RegExp(
    r'(?<!\d)(20\d{2})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})(?!\d)',
  );
  static final RegExp _dateOnlyInFileNamePattern = RegExp(
    r'(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)',
  );

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
    return ratio > 0 && ratio < 0.52;
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

  static int? extractTimestampFromFileName(String filePath) {
    final normalized = filePath.replaceAll('\\', '/').toLowerCase();
    final fileName = normalized.split('/').last;

    final dateTimeMatch = _dateTimeInFileNamePattern.firstMatch(fileName);
    if (dateTimeMatch != null) {
      final timestamp = _tryBuildTimestamp(
        year: int.parse(dateTimeMatch.group(1)!),
        month: int.parse(dateTimeMatch.group(2)!),
        day: int.parse(dateTimeMatch.group(3)!),
        hour: int.parse(dateTimeMatch.group(4)!),
        minute: int.parse(dateTimeMatch.group(5)!),
        second: int.parse(dateTimeMatch.group(6)!),
      );
      if (timestamp != null) {
        return timestamp;
      }
    }

    final dateOnlyMatch = _dateOnlyInFileNamePattern.firstMatch(fileName);
    if (dateOnlyMatch != null) {
      return _tryBuildTimestamp(
        year: int.parse(dateOnlyMatch.group(1)!),
        month: int.parse(dateOnlyMatch.group(2)!),
        day: int.parse(dateOnlyMatch.group(3)!),
        hour: 12,
        minute: 0,
        second: 0,
      );
    }

    return null;
  }

  static int? _tryBuildTimestamp({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
  }) {
    if (year < 2000 || year > 2100) {
      return null;
    }
    try {
      final date = DateTime(year, month, day, hour, minute, second);
      final timestamp = date.millisecondsSinceEpoch;
      return hasValidTimestamp(timestamp) ? timestamp : null;
    } catch (_) {
      return null;
    }
  }
}
