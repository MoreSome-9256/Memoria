/// 应用初始化服务，负责启动时的清理和准备工作

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_album/service/video_cache_service.dart';

class AppInitializer {
  static final AppInitializer instance = AppInitializer._();
  AppInitializer._();

  /// 应用启动时初始化
  Future<void> initialize() async {
    await _initializeCacheDirectories();
  }

  /// 初始化缓存目录（确保目录存在）
  Future<void> _initializeCacheDirectories() async {
    try {
      // 确保缓存目录存在
      await VideoCacheService.instance.getCacheDirectory();
      await VideoCacheService.instance.getExportsDirectory();
      debugPrint('✅ 应用启动：缓存目录初始化完成');
    } catch (e) {
      debugPrint('⚠️ 缓存目录初始化失败: $e');
    }
  }
}