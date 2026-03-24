import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_album/service/auth_token_service.dart';

class MusicService {
  static const String _tokenHeaderName = 'X-Memoria-Token';
  static const Duration _connectTimeout = Duration(seconds: 300);
  static const Duration _sendTimeout = Duration(minutes: 60);
  static const Duration _receiveTimeout = Duration(minutes: 1500);

  static const String _apiBaseUrl = String.fromEnvironment(
    'AUDIO_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const String _apiEndpoint = String.fromEnvironment(
    'AUDIO_API_ENDPOINT',
    defaultValue: '/api/analyze_beats',
  );

  static Future<Map<String, dynamic>?> analyzeAudio(String filePath) async {
    final endpointPath = _apiEndpoint.startsWith('/')
        ? _apiEndpoint.substring(1)
        : _apiEndpoint;
    final requestUri = Uri.parse(_apiBaseUrl).resolve(endpointPath);

    try {
      // 🔐 先获取 Cognito token
      final accessToken = await AuthTokenService.getAccessToken();
      if (accessToken == null) {
        debugPrint("❌ 鉴权失败：无法获取 Cognito Token，请先登录");
        return null;
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: _connectTimeout,
          sendTimeout: _sendTimeout,
          receiveTimeout: _receiveTimeout
        )
      );

      debugPrint(dio.options.listFormat.toString());

      // 🌟 获取真实的带后缀的文件名 (比如 song.m4a)
      final realFileName = p.basename(filePath);

      // 1. 把本地文件打包成 multipart/form-data
      FormData formData = FormData.fromMap({
        "audio": await MultipartFile.fromFile(
          filePath,
          filename: realFileName, // 👈 核心修复：保留真实后缀名！
        ),
      });

      debugPrint("🚀 上传音频分析: POST $requestUri");

      // 2. 发送 POST 请求，并在 header 中添加自定义 token 头
      Response response = await dio.post(
        requestUri.toString(),
        data: formData,
        
        options: Options(
          headers: {
            _tokenHeaderName: accessToken,
          },
        ),

        onSendProgress: (int sent, int total) {
          if (total > 0) {
            debugPrint("上传进度: ${(sent / total * 100).toStringAsFixed(0)}%");
          } else {
            debugPrint("上传进度: $sent bytes");
          }
        },
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Librosa 分析成功! BPM: ${response.data['bpm']}");
        return response.data; // 返回包含 bpm 和 data 的 Map
      } else if (response.statusCode == 401) {
        debugPrint("❌ 鉴权失败 (401)：Token 无效或已过期，请重新登录");
        AuthTokenService.clearCachedToken();
        debugPrint("401 响应体: ${response.data}");
        return null;
      } else {
        debugPrint(
          "❌ 分析失败，状态码: ${response.statusCode}, URL: $requestUri, 响应体: ${response.data}",
        );
        return null;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        debugPrint(
          "❌ 连接超时：在 ${_connectTimeout.inSeconds}s 内无法连上服务。"
          "请检查 API 地址、网络连通性、DNS 和服务端可用性。",
        );
      } else if (e.type == DioExceptionType.sendTimeout) {
        debugPrint("❌ 上传超时：在 ${_sendTimeout.inSeconds}s 内未完成请求发送");
      } else if (e.type == DioExceptionType.receiveTimeout) {
        debugPrint("❌ 响应超时：在 ${_receiveTimeout.inMinutes} 分钟内未收到完整响应");
      }
      debugPrint(
        "❌ DioException: method=${e.requestOptions.method}, url=${e.requestOptions.uri}, "
        "status=${e.response?.statusCode}, data=${e.response?.data}, msg=${e.message}",
      );
      return null;
    } catch (e) {
      debugPrint("❌ 网络或解析错误: $e");
      return null;
    }
  }
}
