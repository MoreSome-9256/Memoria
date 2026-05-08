/// InternVL 输出归档服务，保存和读取模型实验生成的中间结果。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class InternvlOutputArchiveResult {
  const InternvlOutputArchiveResult({
    required this.filePath,
    required this.prettyJson,
  });

  final String filePath;
  final String prettyJson;
}

class InternvlOutputArchiveService {
  Future<InternvlOutputArchiveResult> saveStandardJson({
    required Map<String, dynamic> document,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final archiveDir = Directory('${docs.path}/internvl_outputs');
    if (!archiveDir.existsSync()) {
      archiveDir.createSync(recursive: true);
    }

    final now = DateTime.now();
    final fileName =
        'vlm_output_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.millisecondsSinceEpoch}.json';
    final outputFile = File('${archiveDir.path}/$fileName');

    final encoder = const JsonEncoder.withIndent('  ');
    final pretty = encoder.convert(document);
    await outputFile.writeAsString(pretty, flush: true);

    return InternvlOutputArchiveResult(
      filePath: outputFile.path,
      prettyJson: pretty,
    );
  }
}
