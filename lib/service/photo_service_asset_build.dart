part of 'photo_service.dart';

extension PhotoServiceAssetBuild on PhotoService {
  _PhotoAssetBuilder get _assetBuilder => _PhotoAssetBuilder(this);

  Future<_ScanBuildResult> _buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
  }) {
    return _assetBuilder.buildPhotoEntities(assets, skipExisting: skipExisting);
  }

  Future<_SingleAssetBuildResult> _buildSingleAssetPhoto(AssetEntity asset) {
    return _assetBuilder.buildSingleAssetPhoto(asset);
  }

  Future<File?> _resolveReadableFile(AssetEntity asset) {
    return _assetBuilder.resolveReadableFile(asset);
  }

  void _logAssetExtInfo({
    required AssetEntity asset,
    required String? filePath,
    required LatLng? latLong,
  }) {
    _assetBuilder.logAssetExtInfo(
      asset: asset,
      filePath: filePath,
      latLong: latLong,
    );
  }

  int _resolveBestTimestampMs(AssetEntity asset, File file) {
    return _assetBuilder.resolveBestTimestampMs(asset, file);
  }
}
