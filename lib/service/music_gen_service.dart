import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MusicGenService {
  // 替换成你在 Replicate 申请的 API Token
  static const String _replicateApiToken = String.fromEnvironment(
    'REPLICATE_API_TOKEN',
    defaultValue: '', // 如果没传，默认给个空字符串，方便我们在代码里做判空兜底
  );
  // MusicGen 模型的固定版本号 (这里用的是 facebook/musicgen-small)
  static const String _modelVersion =
      'b05b1dff1d8c6dc63d14b0cdb405cb4a1c488800f8941c93a6d25680075eb207';

  /// 传入 LLM 写的 prompt，生成并下载音乐
  Future<String?> generateAndDownloadMusic(
    String prompt, {
    int duration = 15,
  }) async {
    try {
      // 1. 发起生成请求
      final response = await http.post(
        Uri.parse('https://api.replicate.com/v1/predictions'),
        headers: {
          'Authorization': 'Token $_replicateApiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "version": _modelVersion,
          "input": {
            "prompt": prompt,
            "duration": duration, // 生成多少秒的音乐
            
          },
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('MusicGen 请求失败: ${response.body}');
      }

      // 2. 轮询等待生成完成（AI 写歌通常需要十几秒到半分钟）
      final predictionUrl = jsonDecode(response.body)['urls']['get'];
      String? audioUrl;

      while (true) {
        await Future.delayed(const Duration(seconds: 3));
        final pollResponse = await http.get(
          Uri.parse(predictionUrl),
          headers: {'Authorization': 'Token $_replicateApiToken'},
        );

        final pollData = jsonDecode(pollResponse.body);
        if (pollData['status'] == 'succeeded') {
          audioUrl = pollData['output']; // 拿到生成的 MP3 链接！
          break;
        } else if (pollData['status'] == 'failed') {
          throw Exception('生成音乐失败');
        }
        // status 为 'starting' 或 'processing' 时继续循环
      }

      // 3. 将 MP3 下载到手机沙盒目录
      if (audioUrl != null) {
        final audioRes = await http.get(Uri.parse(audioUrl));
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/ai_bgm_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(audioRes.bodyBytes);

        return file.path; // 返回本地绝对路径，直接喂给你的 librosa / FFmpeg！
      }
    } catch (e) {
      print("❌ AI 音乐生成彻底失败: $e");
    }
    return null;
  }
}
