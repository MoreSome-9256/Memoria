import 'package:shared_preferences/shared_preferences.dart';

class AlbumSelectionSnapshot {
  const AlbumSelectionSnapshot({
    required this.useAllAlbums,
    required this.selectedAlbumIds,
  });

  final bool useAllAlbums;
  final List<String> selectedAlbumIds;
}

class AlbumSelectionPreferenceService {
  static const String _useAllKey = 'album_selection_use_all';
  static const String _selectedIdsKey = 'album_selection_ids';
  static const String _minYearKey = 'scan_min_year';
  static const String _minWidthKey = 'scan_min_width';
  static const String _minHeightKey = 'scan_min_height';

  Future<AlbumSelectionSnapshot> loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final useAll = prefs.getBool(_useAllKey) ?? true;
    final selectedIds = prefs.getStringList(_selectedIdsKey) ?? const <String>[];
    return AlbumSelectionSnapshot(
      useAllAlbums: useAll || selectedIds.isEmpty,
      selectedAlbumIds: selectedIds,
    );
  }

  Future<void> saveSelection({
    required bool useAllAlbums,
    required List<String> selectedAlbumIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAllKey, useAllAlbums);
    await prefs.setStringList(_selectedIdsKey, selectedAlbumIds);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_useAllKey);
    await prefs.remove(_selectedIdsKey);
    await prefs.remove(_minYearKey);
    await prefs.remove(_minWidthKey);
    await prefs.remove(_minHeightKey);
  }

  Future<void> saveScanPreferences({int? minYear, int? minWidth, int? minHeight}) async {
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
  }

  Future<Map<String, int?>> loadScanPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final minYear = prefs.getInt(_minYearKey);
    final minWidth = prefs.getInt(_minWidthKey);
    final minHeight = prefs.getInt(_minHeightKey);
    return {
      'minYear': minYear,
      'minWidth': minWidth,
      'minHeight': minHeight,
    };
  }
}
