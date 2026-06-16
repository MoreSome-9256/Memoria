// 音乐生成服务，负责把故事上下文转换为可播放的音乐资源。

import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'api_proxy_service.dart';

class MusicGenService {
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
      final response = await ApiProxyService.instance
          .post<Map<String, dynamic>>(
            '/v1/replicate/predictions',
            data: {
              "version": _modelVersion,
              "input": {
                "prompt": prompt,
                "duration": duration, // 生成多少秒的音乐
              },
            },
          );

      if (response.statusCode != 201) {
        throw Exception('MusicGen 请求失败: ${response.data}');
      }

      // 2. 轮询等待生成完成（AI 写歌通常需要十几秒到半分钟）
      final predictionId = response.data?['id']?.toString();
      if (predictionId == null || predictionId.isEmpty) {
        throw Exception('MusicGen 返回缺少 prediction id');
      }
      String? audioUrl;

      while (true) {
        await Future.delayed(const Duration(seconds: 3));
        final pollResponse = await ApiProxyService.instance
            .get<Map<String, dynamic>>(
              '/v1/replicate/predictions/$predictionId',
            );

        final pollData = pollResponse.data ?? const <String, dynamic>{};
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
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/ai_bgm_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await ApiProxyService.instance.download(audioUrl, file.path);

        return file.path; // 返回本地绝对路径，直接喂给你的 librosa / FFmpeg！
      }
    } catch (e) {
      print("❌ AI 音乐生成彻底失败: $e");
    }
    return null;
  }
}
