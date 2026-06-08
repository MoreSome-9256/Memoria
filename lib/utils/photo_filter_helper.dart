// 照片过滤辅助工具，负责校验时间戳和解析文件名日期。

class PhotoFilterHelper {
  const PhotoFilterHelper._();

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

  static bool isExtremeAspectRatio(
    int width,
    int height, {
    double maxRatio = 3.2,
  }) {
    if (width <= 0 || height <= 0) return false;
    final longSide = width > height ? width : height;
    final shortSide = width > height ? height : width;
    return longSide / shortSide >= maxRatio;
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
