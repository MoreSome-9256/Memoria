import 'dart:io';

import 'package:flutter/material.dart';

class PathImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  const PathImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme.toLowerCase();

    if (scheme == 'http' || scheme == 'https') {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    final file = _resolveLocalFile(uri);
    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  File _resolveLocalFile(Uri? uri) {
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    return File(path);
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey.shade300,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
