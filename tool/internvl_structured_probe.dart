import 'dart:convert';
import 'dart:io';

import 'package:photo_album/service/internvl_experiment_service.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18081);
  print('[SETUP] Mock server started at http://127.0.0.1:18081');

  final serverTask = () async {
    await for (final req in server) {
      if (req.method != 'POST' || req.uri.path != '/v1/chat/completions') {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }

      final body = await utf8.decoder.bind(req).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final messages = (payload['messages'] as List<dynamic>?) ?? const [];
      final first = messages.isEmpty ? const <String, dynamic>{} : messages.first as Map<String, dynamic>;
      final content = (first['content'] as List<dynamic>?) ?? const [];

      final imageCount = content.where((item) {
        return item is Map<String, dynamic> && item['type'] == 'image_url';
      }).length;

      print('[MOCK] imageCount=$imageCount model=${payload['model']}');

      final responseBody = imageCount == 1
          ? <String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '{"output":{"scene_summary":"校园操场","narrative":"孩子在操场上奔跑","key_facts":["白天","户外"],"visual_entities":["孩子","跑道"],"style_tags":["清新"],"time_location_hints":["学校"],"confidence":0.86}}',
                  },
                },
              ],
            }
          : <String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '这是自然语言回答，不是 JSON。主要是海边和日落。',
                  },
                },
              ],
            };

      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(responseBody));
      await req.response.close();
    }
  }();

  final tempDir = await Directory.systemTemp.createTemp('internvl_structured_');
  final image1 = File('${tempDir.path}/single.jpg');
  final image2 = File('${tempDir.path}/multi.jpg');
  await image1.writeAsBytes(<int>[1, 2, 3]);
  await image2.writeAsBytes(<int>[4, 5, 6]);

  final service = InternvlExperimentService();
  const endpoint = 'http://127.0.0.1:18081/v1/chat/completions';

  try {
    print('[TEST] Single image -> structured JSON expected');
    final single = await service.analyzeImagesStructured(
      serverUrl: endpoint,
      model: 'local-internvl',
      prompt: '请输出结构化 JSON',
      imagePaths: <String>[image1.path],
      maxTokens: 96,
    );
    print('[RESULT] single.usedFallback=${single.usedFallback}');
    print(const JsonEncoder.withIndent('  ').convert(single.normalizedJson));

    print('[TEST] Multi image -> text fallback expected');
    final multi = await service.analyzeImagesStructured(
      serverUrl: endpoint,
      model: 'local-internvl',
      prompt: '请输出结构化 JSON',
      imagePaths: <String>[image1.path, image2.path],
      maxTokens: 96,
    );
    print('[RESULT] multi.usedFallback=${multi.usedFallback}');
    print(const JsonEncoder.withIndent('  ').convert(multi.normalizedJson));
  } finally {
    await server.close(force: true);
    await serverTask;
    await tempDir.delete(recursive: true);
    print('[CLEANUP] Mock server stopped');
  }
}
