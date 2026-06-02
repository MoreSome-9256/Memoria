import 'package:shared_preferences/shared_preferences.dart';

class AlbumSelectionSnapshot {
  const AlbumSelectionSnapshot({
    required this.selectedAlbumIds,
  });

  final List<String> selectedAlbumIds;
}

class ScanFilterPreferences {
  const ScanFilterPreferences({
    this.minYear,
    this.minWidth,
    this.minHeight,
    this.minPixels,
    this.excludeExtremeAspectRatios = false,
  });

  final int? minYear;
  final int? minWidth;
  final int? minHeight;
  final int? minPixels;
  final bool excludeExtremeAspectRatios;

  bool get hasMinResolution => minWidth != null && minHeight != null;
  bool get hasAnyRule =>
      minYear != null ||
      hasMinResolution ||
      minPixels != null ||
      excludeExtremeAspectRatios;

  String get summary {
    if (!hasAnyRule) return '不限制';
    final parts = <String>[];
    if (minYear != null) parts.add('$minYear 年之后');
    if (hasMinResolution) parts.add('不低于 ${minWidth}x$minHeight');
    if (minPixels != null) {
      final mp = minPixels! / 1000000.0;
      parts.add('不低于 ${mp.toStringAsFixed(mp >= 1 ? 0 : 1)}MP');
    }
    if (excludeExtremeAspectRatios) parts.add('排除超宽/超长图');
    return parts.join('，');
  }
}

class AlbumSelectionPreferenceService {
  static const String _selectedIdsKey = 'album_selection_ids';
  static const String _minYearKey = 'scan_min_year';
  static const String _minWidthKey = 'scan_min_width';
  static const String _minHeightKey = 'scan_min_height';
  static const String _minPixelsKey = 'scan_min_pixels';
  static const String _excludeScreenshotsKey = 'scan_exclude_screenshots';
  static const String _excludeExtremeAspectRatiosKey =
      'scan_exclude_extreme_aspect_ratios';

  /// 默认使用系统当前已授权范围。只有用户显式保存白名单时才按相册过滤。
  static const List<String> defaultAlbumIds = <String>[];

  Future<AlbumSelectionSnapshot> loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedIds =
        prefs.getStringList(_selectedIdsKey) ?? defaultAlbumIds;
    return AlbumSelectionSnapshot(selectedAlbumIds: selectedIds);
  }

  Future<void> saveSelection({
    required List<String> selectedAlbumIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deduped = selectedAlbumIds.toSet().toList(growable: false)..sort();
    await prefs.setStringList(_selectedIdsKey, deduped);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedIdsKey);
    await prefs.remove(_minYearKey);
    await prefs.remove(_minWidthKey);
    await prefs.remove(_minHeightKey);
    await prefs.remove(_minPixelsKey);
    await prefs.remove(_excludeScreenshotsKey);
    await prefs.remove(_excludeExtremeAspectRatiosKey);
  }

  Future<void> saveScanPreferences({
    int? minYear,
    int? minWidth,
    int? minHeight,
    int? minPixels,
    bool excludeExtremeAspectRatios = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (minYear == null) {
      await prefs.remove(_minYearKey);
    } else {
      await prefs.setInt(_minYearKey, minYear);
    }
    if (minWidth == null) {
      await prefs.remove(_minWidthKey);
    } else {
      await prefs.setInt(_minWidthKey, minWidth);
    }
    if (minHeight == null) {
      await prefs.remove(_minHeightKey);
    } else {
      await prefs.setInt(_minHeightKey, minHeight);
    }
    if (minPixels == null) {
      await prefs.remove(_minPixelsKey);
    } else {
      await prefs.setInt(_minPixelsKey, minPixels);
    }
    await prefs.remove(_excludeScreenshotsKey);
    await prefs.setBool(
      _excludeExtremeAspectRatiosKey,
      excludeExtremeAspectRatios,
    );
  }

  Future<ScanFilterPreferences> loadScanPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final minYear = prefs.getInt(_minYearKey);
    final minWidth = prefs.getInt(_minWidthKey);
    final minHeight = prefs.getInt(_minHeightKey);
    final minPixels = prefs.getInt(_minPixelsKey);
    return ScanFilterPreferences(
      minYear: minYear,
      minWidth: minWidth,
      minHeight: minHeight,
      minPixels: minPixels,
      excludeExtremeAspectRatios:
          prefs.getBool(_excludeExtremeAspectRatiosKey) ?? false,
    );
  }
}
