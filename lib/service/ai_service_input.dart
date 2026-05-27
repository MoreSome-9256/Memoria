/// AI 服务的输入模型，定义单次分析所需的照片与控制参数。

part of 'ai_service.dart';

enum _AnalysisInputStrategy {
  thumbnailFirst('thumbnail_first'),
  originalFirst('original_first'),
  thumbnailTimeout('thumbnail_timeout');

  const _AnalysisInputStrategy(this.label);

  final String label;

  static _AnalysisInputStrategy parse(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    return switch (normalized) {
      'original_first' => _AnalysisInputStrategy.originalFirst,
      'thumbnail_timeout' => _AnalysisInputStrategy.thumbnailTimeout,
      _ => _AnalysisInputStrategy.thumbnailFirst,
    };
  }
}

class _AnalysisInputConfig {
  const _AnalysisInputConfig({
    required this.strategy,
    required this.thumbnailTimeout,
  });

  factory _AnalysisInputConfig.resolve({
    required String strategyLabel,
    required String thumbnailTimeoutMsLabel,
  }) {
    final timeoutMs = int.tryParse(thumbnailTimeoutMsLabel.trim()) ?? 120;
    final boundedTimeoutMs = timeoutMs.clamp(1, 5000).toInt();
    return _AnalysisInputConfig(
      strategy: _AnalysisInputStrategy.parse(strategyLabel),
      thumbnailTimeout: Duration(milliseconds: boundedTimeoutMs),
    );
  }

  final _AnalysisInputStrategy strategy;
  final Duration thumbnailTimeout;
}

class _AnalysisInputLoader {
  const _AnalysisInputLoader({
    required this.config,
    required this.thumbnailSize,
  });

  final _AnalysisInputConfig config;
  final ThumbnailSize thumbnailSize;

  Future<_PreparedAnalysisInput?> load(PhotoEntity photo) async {
    final file = await PhotoService().openOriginalMediaFile(
      photo,
      purpose: 'ai_service_input',
    );

    final loadWatch = Stopwatch()..start();
    Uint8List? mobileClipBytes;
    var thumbnailReadMs = 0.0;
    var fileReadMs = 0.0;
    var inputSource = 'original_file';
    var thumbnailAttempted = false;
    var thumbnailTimedOut = false;
    var fallbackToOriginal = false;
    var fallbackReason = 'none';

    if (config.strategy == _AnalysisInputStrategy.originalFirst) {
      final fileResult = await _readOriginalFileBytes(file);
      mobileClipBytes = fileResult.bytes;
      fileReadMs = fileResult.readMs;
    } else {
      final thumbnailResult = await _tryReadThumbnailBytes(
        photo,
        timeout: config.strategy == _AnalysisInputStrategy.thumbnailTimeout
            ? config.thumbnailTimeout
            : null,
      );
      mobileClipBytes = thumbnailResult.bytes;
      thumbnailReadMs = thumbnailResult.readMs;
      thumbnailAttempted = thumbnailResult.attempted;
      thumbnailTimedOut = thumbnailResult.timedOut;
      if (thumbnailResult.hasBytes) {
        inputSource = 'thumbnail';
      } else {
        fallbackToOriginal = true;
        fallbackReason = thumbnailResult.fallbackReason;
        final fileResult = await _readOriginalFileBytes(file);
        mobileClipBytes = fileResult.bytes;
        fileReadMs = fileResult.readMs;
      }
    }

    if (mobileClipBytes == null || mobileClipBytes.isEmpty) {
      return null;
    }
    loadWatch.stop();

    return _PreparedAnalysisInput(
      photo: photo,
      file: file,
      mobileClipBytes: mobileClipBytes,
      usedThumbnail: inputSource == 'thumbnail',
      inputSource: inputSource,
      inputStrategy: config.strategy.label,
      thumbnailAttempted: thumbnailAttempted,
      thumbnailTimedOut: thumbnailTimedOut,
      fallbackToOriginal: fallbackToOriginal,
      fallbackReason: fallbackReason,
      loadMs: loadWatch.elapsedMicroseconds / 1000.0,
      thumbnailReadMs: thumbnailReadMs,
      fileReadMs: fileReadMs,
    );
  }

  Future<_ThumbnailReadAttempt> _tryReadThumbnailBytes(
    PhotoEntity photo, {
    required Duration? timeout,
  }) async {
    final thumbnailWatch = Stopwatch()..start();
    try {
      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        thumbnailWatch.stop();
        return _ThumbnailReadAttempt(
          bytes: null,
          readMs: thumbnailWatch.elapsedMicroseconds / 1000.0,
          attempted: true,
          timedOut: false,
          fallbackReason: 'asset_unavailable',
        );
      }

      final future = asset.thumbnailDataWithSize(thumbnailSize);
      final bytes = timeout == null
          ? await future
          : await future.timeout(timeout);
      thumbnailWatch.stop();
      final hasBytes = bytes != null && bytes.isNotEmpty;
      return _ThumbnailReadAttempt(
        bytes: bytes,
        readMs: thumbnailWatch.elapsedMicroseconds / 1000.0,
        attempted: true,
        timedOut: false,
        fallbackReason: hasBytes ? 'none' : 'thumbnail_empty',
      );
    } on TimeoutException {
      thumbnailWatch.stop();
      return _ThumbnailReadAttempt(
        bytes: null,
        readMs: thumbnailWatch.elapsedMicroseconds / 1000.0,
        attempted: true,
        timedOut: true,
        fallbackReason: 'thumbnail_timeout',
      );
    } catch (error) {
      thumbnailWatch.stop();
      debugPrint('读取系统缩略图失败 photoId=${photo.id}: $error');
      return _ThumbnailReadAttempt(
        bytes: null,
        readMs: thumbnailWatch.elapsedMicroseconds / 1000.0,
        attempted: true,
        timedOut: false,
        fallbackReason: 'thumbnail_error',
      );
    }
  }

  Future<_OriginalFileReadResult> _readOriginalFileBytes(File file) async {
    final fileReadWatch = Stopwatch()..start();
    final bytes = await file.readAsBytes();
    fileReadWatch.stop();
    return _OriginalFileReadResult(
      bytes: bytes,
      readMs: fileReadWatch.elapsedMicroseconds / 1000.0,
    );
  }
}

class _ThumbnailReadAttempt {
  const _ThumbnailReadAttempt({
    required this.bytes,
    required this.readMs,
    required this.attempted,
    required this.timedOut,
    required this.fallbackReason,
  });

  final Uint8List? bytes;
  final double readMs;
  final bool attempted;
  final bool timedOut;
  final String fallbackReason;

  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

class _OriginalFileReadResult {
  const _OriginalFileReadResult({required this.bytes, required this.readMs});

  final Uint8List bytes;
  final double readMs;
}
