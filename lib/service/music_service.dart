import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class MusicService {
  // ⚠️ 极其重要：如果后端在你本地电脑上跑，这里千万别写 localhost 或 127.0.0.1！
  // 必须写你电脑的局域网 IPv4 地址 (比如 192.168.1.100)
  static const String _baseUrl = "http://127.0.0.1:8000";

  static Future<Map<String, dynamic>?> analyzeAudio(String filePath) async {
    try {
      final dio = Dio();

      // 1. 把本地文件打包成 multipart/form-data
      FormData formData = FormData.fromMap({
        "audio": await MultipartFile.fromFile(
          filePath,
          filename: "upload_audio.mp3",
        ),
      });

      debugPrint("🚀 正在上传音频到云端进行 Librosa 分析...");

      // 2. 发送 POST 请求
      Response response = await dio.post(
        "$_baseUrl/api/analyze_beats",
        data: formData,
        // 可以加个进度条监听
        onSendProgress: (int sent, int total) {
          debugPrint("上传进度: ${(sent / total * 100).toStringAsFixed(0)}%");
        },
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Librosa 分析成功! BPM: ${response.data['bpm']}");
        return response.data; // 返回包含 bpm 和 data 的 Map
      } else {
        debugPrint("❌ 分析失败，状态码: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ 网络或解析错误: $e");
      return null;
    }
  }
}
