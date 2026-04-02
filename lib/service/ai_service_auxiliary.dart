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
    required this.source,
    required this.createdTemporaryFile,
  });

  final File file;
  final String source;
  final bool createdTemporaryFile;
}

class _AnalysisFileResolver {
  const _AnalysisFileResolver({
    required this.config,
    required this.createCompressedFile,
  });

  final _AnalysisAuxiliaryConfig config;
  final Future<File> Function(File sourceFile, int photoId)
  createCompressedFile;

  Future<_ResolvedAnalysisFile> resolve({
    required File sourceFile,
    required int photoId,
  }) async {
    switch (config.strategy) {
      case _AnalysisAuxiliaryStrategy.useOriginal:
        return _ResolvedAnalysisFile(
          file: sourceFile,
          source: 'source_file',
          createdTemporaryFile: false,
        );
      case _AnalysisAuxiliaryStrategy.alwaysCompress:
        final file = await createCompressedFile(sourceFile, photoId);
        return _ResolvedAnalysisFile(
          file: file,
          source: 'compressed_temp',
          createdTemporaryFile: true,
        );
    }
  }
}
