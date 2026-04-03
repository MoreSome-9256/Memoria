part of 'photo_service.dart';

class _PreparedScanData {
  const _PreparedScanData({
    required this.assets,
    required this.totalCount,
    required this.fetchCount,
    required this.startOffset,
  });

  final List<AssetEntity> assets;
  final int totalCount;
  final int fetchCount;
  final int startOffset;
}

class _ScanBuildResult {
  const _ScanBuildResult({
    required this.photos,
    required this.insertedCount,
    required this.insertedNoGps,
    required this.skippedInvalidTime,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });

  final List<PhotoEntity> photos;
  final int insertedCount;
  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
}

class _PhotoRebuildPlan {
  const _PhotoRebuildPlan({
    required this.totalBefore,
    required this.prepared,
    required this.built,
  });

  final int totalBefore;
  final _PreparedScanData prepared;
  final _ScanBuildResult built;
}

class _PhotoSyncPlan {
  const _PhotoSyncPlan({
    required this.totalBefore,
    required this.prepared,
    required this.removedCount,
    required this.built,
  });

  final int totalBefore;
  final _PreparedScanData prepared;
  final int removedCount;
  final _ScanBuildResult built;
}

class _SingleAssetBuildResult {
  const _SingleAssetBuildResult({
    this.photo,
    this.insertedNoGps = 0,
    this.skippedInvalidTime = 0,
    this.skippedNonCamera = 0,
    this.skippedScreenshot = 0,
  });

  final PhotoEntity? photo;
  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
}

class _PhotoAccessCacheEntry {
  const _PhotoAccessCacheEntry({
    required this.checkedAtMs,
    this.resolvedPath,
    this.isRemoved = false,
  });

  final int checkedAtMs;
  final String? resolvedPath;
  final bool isRemoved;
}

enum PhotoScanError { permissionDenied, noAlbum, noEligiblePhoto }

class PhotoScanException implements Exception {
  final PhotoScanError code;
  final String message;

  const PhotoScanException(this.code, this.message);

  @override
  String toString() {
    return message;
  }
}

class PhotoScanSummary {
  final int totalBefore;
  final int totalAfter;
  final int removedCount;
  final int insertedCount;
  final List<int> insertedPhotoIds;
  final int scanStartOffset;
  final int scannedCount;
  final int skippedInvalidTime;
  final int insertedNoGps;
  final int skippedNonCamera;
  final int skippedScreenshot;

  const PhotoScanSummary({
    required this.totalBefore,
    required this.totalAfter,
    required this.removedCount,
    required this.insertedCount,
    this.insertedPhotoIds = const <int>[],
    this.scanStartOffset = 0,
    this.scannedCount = 0,
    required this.skippedInvalidTime,
    required this.insertedNoGps,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });
}
