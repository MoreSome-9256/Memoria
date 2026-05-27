import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum AiModelWeightId {
  mobileclip2LiteRt,
  mobileclipNcnn,
  mobileViClipSmall,
  smolVlm2,
}

extension AiModelWeightIdX on AiModelWeightId {
  String get storageKey => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'mobileclip2_litert',
    AiModelWeightId.mobileclipNcnn => 'mobileclip_ncnn',
    AiModelWeightId.mobileViClipSmall => 'mobileviclip_small',
    AiModelWeightId.smolVlm2 => 'smolvlm2',
  };

  String get label => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'MobileCLIP2 LiteRT',
    AiModelWeightId.mobileclipNcnn => 'MobileCLIP NCNN',
    AiModelWeightId.mobileViClipSmall => 'MobileViCLIP Small',
    AiModelWeightId.smolVlm2 => 'SmolVLM2 描述模型',
  };

  String get description => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => '图片标签、文本向量和图片语义检索',
    AiModelWeightId.mobileclipNcnn => 'NCNN/Vulkan 方向的图片向量后端',
    AiModelWeightId.mobileViClipSmall => '视频和动态照片的时序向量',
    AiModelWeightId.smolVlm2 => '开发者工具中的图片/视频描述',
  };

  List<String> get relativePaths => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => const <String>[
      'mobileclip2/s2/mobileclip2_s2_image.tflite',
      'mobileclip2/s2/mobileclip2_s2_text.tflite',
    ],
    AiModelWeightId.mobileclipNcnn => const <String>[
      'ncnn/mobileclip_s2/image.param',
      'ncnn/mobileclip_s2/image.bin',
      'ncnn/mobileclip_s2/text.param',
      'ncnn/mobileclip_s2/text.bin',
    ],
    AiModelWeightId.mobileViClipSmall => const <String>[
      'mobileviclip/small/mobileviclip_small.onnx',
    ],
    AiModelWeightId.smolVlm2 => const <String>[
      'smolvlm2/smolvlm2.gguf',
      'smolvlm2/mmproj.gguf',
    ],
  };
}

class AiModelWeightStatus {
  const AiModelWeightStatus({
    required this.id,
    required this.presentFiles,
    required this.missingFiles,
    required this.checkPassed,
  });

  final AiModelWeightId id;
  final List<String> presentFiles;
  final List<String> missingFiles;
  final bool checkPassed;

  bool get hasDownloadedFiles => presentFiles.isNotEmpty;
}

class AiModelWeightService {
  AiModelWeightService._();
  static final AiModelWeightService instance = AiModelWeightService._();

  Future<bool> ensureWeightsAvailableForInference(AiModelWeightId id) async {
    // Current release still ships model assets with the app or relies on local
    // developer files. The future downloader will replace this stub with a real
    // filesystem check and user-facing remediation path.
    return true;
  }

  Future<Directory> modelRootDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}models');
  }

  Future<List<AiModelWeightStatus>> loadStatuses() async {
    final root = await modelRootDirectory();
    final statuses = <AiModelWeightStatus>[];
    for (final id in AiModelWeightId.values) {
      final present = <String>[];
      final missing = <String>[];
      for (final relativePath in id.relativePaths) {
        final file = File(_join(root.path, relativePath));
        if (await file.exists()) {
          present.add(relativePath);
        } else {
          missing.add(relativePath);
        }
      }
      statuses.add(
        AiModelWeightStatus(
          id: id,
          presentFiles: present,
          missingFiles: missing,
          checkPassed: await ensureWeightsAvailableForInference(id),
        ),
      );
    }
    return statuses;
  }

  Future<void> deleteDownloadedWeights(AiModelWeightId id) async {
    final root = await modelRootDirectory();
    for (final relativePath in id.relativePaths) {
      final file = File(_join(root.path, relativePath));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> downloadWeights(AiModelWeightId id) async {
    throw UnimplementedError('模型互联网下载将在后续版本启用: ${id.label}');
  }

  String _join(String root, String relativePath) {
    return relativePath
        .split('/')
        .fold(
          root,
          (path, segment) => '$path${Platform.pathSeparator}$segment',
        );
  }
}
