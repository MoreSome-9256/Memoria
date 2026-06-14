import 'package:flutter/material.dart';

import '../../models/vo/photo.dart';
import 'asset_backed_image.dart';

class PhotoImage extends StatelessWidget {
  const PhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.enableSmartCache = true,
  });

  final Photo photo;
  final BoxFit fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final bool enableSmartCache;

  @override
  Widget build(BuildContext context) {
    return AssetBackedImage(
      path: photo.path,
      assetId: photo.id,
      thumbnailBytes: photo.thumbnailBytes,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      enableSmartCache: enableSmartCache,
    );
  }
}
