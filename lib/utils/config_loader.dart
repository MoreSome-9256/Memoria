import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 应用配置加载器
/// 用于加载 config/profiles/dev.json 等配置文件
class ConfigLoader {
  static Map<String, dynamic>? _cachedConfig;
  
  /// 从 assets 加载配置文件
  static Future<Map<String, dynamic>> loadConfig({
    String profile = 'dev',
  }) async {
    // 如果已缓存，直接返回
    if (_cachedConfig != null) {
      return _cachedConfig!;
    }
    
    try {
      final configString = await rootBundle.loadString(
        'assets/config/profiles/$profile.json',
      );
      _cachedConfig = jsonDecode(configString);
      debugPrint('✅ 配置加载成功: profiles/$profile.json');
      return _cachedConfig!;
    } catch (e) {
      debugPrint('❌ 无法加载配置文件: $e');
      
      // 兜底方案：返回默认配置
      _cachedConfig = {
        'AWS_REGION': 'ap-southeast-1',
        'AUDIO_API_BASE_URL': 'http://127.0.0.1:8000',
        'AUDIO_API_ENDPOINT': '/api/analyze_beats',
      };
      return _cachedConfig!;
    }
  }
  
  /// 获取单个配置项
  static Future<String?> getConfigValue(
    String key, {
    String profile = 'dev',
  }) async {
    final config = await loadConfig(profile: profile);
    return config[key]?.toString();
  }
  
  /// 清除缓存配置（主要用于测试）
  static void clearCache() {
    _cachedConfig = null;
    debugPrint('🧹 已清除配置缓存');
  }
}
