/// AI 服务的辅助逻辑分组，放置共享的工具方法和小型流程封装。

part of 'ai_service.dart';

enum _AnalysisAuxiliaryStrategy {
  alwaysCompress('always_compress'),
  useOriginal('use_original');

  const _AnalysisAuxiliaryStrategy(this.label);

  final String label;

  static _AnalysisAuxiliaryStrategy parse(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    return switch (normalized) {
      'use_original' => _AnalysisAuxiliaryStrategy.useOriginal,
      _ => _AnalysisAuxiliaryStrategy.alwaysCompress,
    };
  }
}

class _AnalysisAuxiliaryConfig {
  const _AnalysisAuxiliaryConfig({required this.strategy});

  factory _AnalysisAuxiliaryConfig.resolve({required String strategyLabel}) {
    return _AnalysisAuxiliaryConfig(
      strategy: _AnalysisAuxiliaryStrategy.parse(strategyLabel),
    );
  }

  final _AnalysisAuxiliaryStrategy strategy;
}

class _ResolvedAnalysisFile {
  const _ResolvedAnalysisFile({
    required this.file,
    required this.sourceBytes,
    required this.source,
    required this.createdTemporaryFile,
  });

  final File file;
  final Uint8List? sourceBytes;
  final String source;
  final bool createdTemporaryFile;
}

class _CreatedAnalysisFile {
  const _CreatedAnalysisFile({required this.file, required this.bytes});

  final File file;
  final Uint8List bytes;
}

class _AnalysisFileResolver {
  const _AnalysisFileResolver({
    required this.config,
    required this.createCompressedFile,
  });

  final _AnalysisAuxiliaryConfig config;
  final Future<_CreatedAnalysisFile> Function(File sourceFile, int photoId)
  createCompressedFile;

  Future<_ResolvedAnalysisFile> resolve({
    required File sourceFile,
    required int photoId,
  }) async {
    switch (config.strategy) {
      case _AnalysisAuxiliaryStrategy.useOriginal:
        return _ResolvedAnalysisFile(
          file: sourceFile,
          sourceBytes: null,
          source: 'source_file',
          createdTemporaryFile: false,
        );
      case _AnalysisAuxiliaryStrategy.alwaysCompress:
        final created = await createCompressedFile(sourceFile, photoId);
        return _ResolvedAnalysisFile(
          file: created.file,
          sourceBytes: created.bytes,
          source: 'compressed_temp',
          createdTemporaryFile: true,
        );
    }
  }
}
