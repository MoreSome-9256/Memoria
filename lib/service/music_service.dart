import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import '../utils/config_loader.dart';

class MusicService {
  // 🔐 Cognito 鉴权相关
  static String? _cachedAccessToken;
  static DateTime? _tokenExpiryTime;

  /// 从 Cognito 获取访问 token
  static Future<String?> _getCognitoAccessToken() async {
    try {
      // 🔐 首先检查缓存的 token 是否仍然有效
      if (_cachedAccessToken != null && _tokenExpiryTime != null) {
        if (DateTime.now().isBefore(_tokenExpiryTime!.subtract(Duration(minutes: 5)))) {
          debugPrint("✅ 使用缓存的 Cognito Token");
          return _cachedAccessToken;
        }
      }
      
      // 获取认证会话
      final cognitoPlugin = Amplify.Auth.getPlugin(AmplifyAuthCognito.pluginKey);
      final session = await cognitoPlugin.fetchAuthSession();
      if (!session.isSignedIn) {
        debugPrint("❌ 用户会话不有效");
        return null;
      }
      
      // 🔐 获取 access token（用于 API 鉴权）
      final accessToken = session.userPoolTokensResult.valueOrNull?.accessToken.raw;
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint("❌ 无法获取 Cognito access token");
        return null;
      }
      
      // 💾 缓存 token 和过期时间（通常 token 有效期为 1 小时）
      _cachedAccessToken = accessToken;
      _tokenExpiryTime = DateTime.now().add(const Duration(minutes: 55));
      
      debugPrint("✅ 成功获取 Cognito Token (缓存 55 分钟)");
      return accessToken;
      
    } catch (e) {
      debugPrint("❌ 获取 Cognito Token 失败: $e");
      return null;
    }
  }
  
  /// 清除缓存的 token（用户登出时调用）
  static void clearCachedToken() {
    _cachedAccessToken = null;
    _tokenExpiryTime = null;
    debugPrint("🧹 已清除缓存的 Cognito Token");
  }

  static Future<Map<String, dynamic>?> analyzeAudio(String filePath) async {
    try {
      // 🔐 先获取 Cognito token
      final accessToken = await _getCognitoAccessToken();
      if (accessToken == null) {
        debugPrint("❌ 鉴权失败：无法获取 Cognito Token，请先登录");
        return null;
      }
      
      // 📝 读取配置
      final baseUrl = await ConfigLoader.getConfigValue('AUDIO_API_BASE_URL') ?? 
                      "http://127.0.0.1:8000";
      final endpoint = await ConfigLoader.getConfigValue('AUDIO_API_ENDPOINT') ?? 
                       "/api/analyze_beats";
      
      final dio = Dio();

      // 🌟 获取真实的带后缀的文件名 (比如 song.m4a)
      String realFileName = filePath.split('/').last;

      // 1. 把本地文件打包成 multipart/form-data
      FormData formData = FormData.fromMap({
        "audio": await MultipartFile.fromFile(
          filePath,
          filename: realFileName, // 👈 核心修复：保留真实后缀名！
        ),
      });

      debugPrint("🚀 正在上传音频到云端进行 Librosa 分析... (已鉴权)");

      // 2. 发送 POST 请求，并在 header 中添加 Authorization
      Response response = await dio.post(
        "$baseUrl$endpoint",
        data: formData,
        options: Options(
          headers: {
            // 🔐 关键：添加 Bearer token 用于 Cognito 鉴权
            "Authorization": "Bearer $accessToken",
          },
        ),
        onSendProgress: (int sent, int total) {
          debugPrint("上传进度: ${(sent / total * 100).toStringAsFixed(0)}%");
        },
      );

      if (response.statusCode == 200) {
        debugPrint("✅ Librosa 分析成功! BPM: ${response.data['bpm']}");
        return response.data; // 返回包含 bpm 和 data 的 Map
      } else if (response.statusCode == 401) {
        debugPrint("❌ 鉴权失败 (401)：Token 无效或已过期，请重新登录");
        clearCachedToken(); // 清除无效的缓存 token
        return null;
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
