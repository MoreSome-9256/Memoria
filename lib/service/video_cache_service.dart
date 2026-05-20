/// 视频缓存服务，负责管理视频文件的生成、缓存和清理
/// 确保每个session只生成一个视频，合理管理文件存储位置

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

class VideoCacheService {
  static final VideoCacheService instance = VideoCacheService._();
  VideoCacheService._();

  // 缓存配置
  static const String _cacheSubdir = 'VideoCache';
  static const String _exportsSubdir = 'StoryExports';
  static const Duration _cacheDuration = Duration(days: 7); // 缓存保留7天
  
  // 内存缓存：sessionId -> 视频路径
  final Map<String, String> _sessionCache = {};

  /// 生成session ID（基于图片和文本的哈希）
  /// 只检查图片路径和文本是否一致，不检查其他参数
  String _generateSessionId({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> sections,
    required String? customMusicPath,
    required Map<String, dynamic>? dynamicBeatData,
    required String targetPlatform,
    required bool isHorizontal,
    required String currentTextStyle,
    required double textYPosition,
    required double textSize,
    required double textBlurIntensity,
    required double shakeIntensity,
    required double shakeFrequency,
    required double glitchIntensity,
    required bool enableFlash,
    required bool useVignette,
    required bool useGrain,
    required bool useCameraFrame,
    required bool useGlowRing,
    required bool useCloudBorder,
  }) {
    // 只提取图片路径和文本
    final imageTextData = {
      // 提取所有图片路径，按路径排序确保一致性
      'images': sections.map((s) => s['photo']['path'] as String).toList()..sort(),
      // 提取所有文本
      'texts': sections.map((s) => s['text'] as String).toList(),
    };
    
    final jsonString = jsonEncode(imageTextData);
    final bytes = utf8.encode(jsonString);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 获取缓存目录（用户不可见，自动清理）
  Future<Directory> getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(path.join(tempDir.path, _cacheSubdir));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 获取导出目录（用户可见，需要保持整洁）
  Future<Directory> getExportsDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(path.join(docDir.path, _exportsSubdir));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    return exportsDir;
  }

  /// 检查是否已有缓存的视频
  /// 只检查图片和文本是否一致
  Future<String?> getCachedVideoPath({
    required List<Map<String, dynamic>> sections,
  }) async {
    // 简化参数，只传递sections
    final sessionId = _generateSessionId(
      title: '', // 不使用
      subtitle: '', // 不使用
      sections: sections,
      customMusicPath: null, // 不使用
      dynamicBeatData: null, // 不使用
      targetPlatform: '', // 不使用
      isHorizontal: false, // 不使用
      currentTextStyle: '', // 不使用
      textYPosition: 0, // 不使用
      textSize: 0, // 不使用
      textBlurIntensity: 0, // 不使用
      shakeIntensity: 0, // 不使用
      shakeFrequency: 0, // 不使用
      glitchIntensity: 0, // 不使用
      enableFlash: false, // 不使用
      useVignette: false, // 不使用
      useGrain: false, // 不使用
      useCameraFrame: false, // 不使用
      useGlowRing: false, // 不使用
      useCloudBorder: false, // 不使用
    );

    // 检查内存缓存
    if (_sessionCache.containsKey(sessionId)) {
      final cachedPath = _sessionCache[sessionId]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      } else {
        _sessionCache.remove(sessionId);
      }
    }

    // 检查文件缓存
    final cacheDir = await getCacheDirectory();
    final cachedFile = File(path.join(cacheDir.path, '$sessionId.mp4'));
    
    if (await cachedFile.exists()) {
      _sessionCache[sessionId] = cachedFile.path;
      return cachedFile.path;
    }

    return null;
  }

  /// 缓存视频文件
  /// 只基于图片和文本进行缓存
  Future<String> cacheVideo({
    required List<Map<String, dynamic>> sections,
    required String videoPath,
  }) async {
    // 简化参数，只传递sections
    final sessionId = _generateSessionId(
      title: '', // 不使用
      subtitle: '', // 不使用
      sections: sections,
      customMusicPath: null, // 不使用
      dynamicBeatData: null, // 不使用
      targetPlatform: '', // 不使用
      isHorizontal: false, // 不使用
      currentTextStyle: '', // 不使用
      textYPosition: 0, // 不使用
      textSize: 0, // 不使用
      textBlurIntensity: 0, // 不使用
      shakeIntensity: 0, // 不使用
      shakeFrequency: 0, // 不使用
      glitchIntensity: 0, // 不使用
      enableFlash: false, // 不使用
      useVignette: false, // 不使用
      useGrain: false, // 不使用
      useCameraFrame: false, // 不使用
      useGlowRing: false, // 不使用
      useCloudBorder: false, // 不使用
    );

    final cacheDir = await getCacheDirectory();
    final cachedPath = path.join(cacheDir.path, '$sessionId.mp4');
    
    // 复制到缓存目录
    await File(videoPath).copy(cachedPath);
    
    // 更新内存缓存
    _sessionCache[sessionId] = cachedPath;
    
    return cachedPath;
  }

  /// 将视频移动到导出目录（用户可见）
  Future<String> moveToExportsDirectory(String sourcePath, {String? customName}) async {
    final exportsDir = await getExportsDirectory();
    final fileName = customName ?? 'Story_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final destPath = path.join(exportsDir.path, fileName);
    
    await File(sourcePath).copy(destPath);
    
    // 清理旧的导出文件（保留最近10个）
    await _cleanOldExports(exportsDir, keepCount: 10);
    
    return destPath;
  }

  /// 清理旧的导出文件
  Future<void> _cleanOldExports(Directory exportsDir, {int keepCount = 10}) async {
    try {
      final files = await exportsDir.list().toList();
      final videoFiles = files.whereType<File>().where((file) {
        return file.path.toLowerCase().endsWith('.mp4');
      }).toList();
      
      if (videoFiles.length > keepCount) {
        // 按修改时间排序
        videoFiles.sort((a, b) {
          return b.statSync().modified.compareTo(a.statSync().modified);
        });
        
        // 删除最旧的文件
        for (int i = keepCount; i < videoFiles.length; i++) {
          try {
            await videoFiles[i].delete();
          } catch (e) {
            debugPrint('清理旧文件失败: ${videoFiles[i].path} - $e');
          }
        }
      }
    } catch (e) {
      debugPrint('清理导出目录失败: $e');
    }
  }

  /// 清理临时文件（仅清理本次导出产生的临时文件）
  Future<void> cleanupExportTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = await tempDir.list().toList();
      
      for (var file in files) {
        if (file is File) {
          final fileName = path.basename(file.path);
          // 仅删除本次导出产生的临时文件
          if (fileName.startsWith('silent_temp_') || 
              fileName.startsWith('temp_audio_') ||
              fileName.startsWith('safe_custom_audio_')) {
            try {
              await file.delete();
            } catch (e) {
              // 忽略删除错误
            }
          }
        }
      }
    } catch (e) {
      debugPrint('清理临时文件失败: $e');
    }
  }

  /// 手动清理所有缓存文件（从profile page调用）
  Future<void> clearAllCache() async {
    try {
      // 清理缓存目录
      final cacheDir = await getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        debugPrint('✅ 已清理缓存目录: ${cacheDir.path}');
      }
      
      // 清理内存缓存
      _sessionCache.clear();
      
      // 重新创建缓存目录
      await cacheDir.create(recursive: true);
      
      return;
    } catch (e) {
      debugPrint('❌ 清理缓存失败: $e');
      rethrow;
    }
  }

  /// 获取缓存统计信息
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final cacheDir = await getCacheDirectory();
      final exportsDir = await getExportsDirectory();
      
      int cacheFileCount = 0;
      int cacheTotalSize = 0;
      int exportFileCount = 0;
      int exportTotalSize = 0;
      
      if (await cacheDir.exists()) {
        final cacheFiles = await cacheDir.list().toList();
        for (var file in cacheFiles) {
          if (file is File) {
            cacheFileCount++;
            final stat = await file.stat();
            cacheTotalSize += stat.size;
          }
        }
      }
      
      if (await exportsDir.exists()) {
        final exportFiles = await exportsDir.list().toList();
        for (var file in exportFiles) {
          if (file is File && file.path.toLowerCase().endsWith('.mp4')) {
            exportFileCount++;
            final stat = await file.stat();
            exportTotalSize += stat.size;
          }
        }
      }
      
      return {
        'cacheFileCount': cacheFileCount,
        'cacheTotalSize': cacheTotalSize,
        'cacheSizeFormatted': _formatFileSize(cacheTotalSize),
        'exportFileCount': exportFileCount,
        'exportTotalSize': exportTotalSize,
        'exportSizeFormatted': _formatFileSize(exportTotalSize),
        'memoryCacheCount': _sessionCache.length,
      };
    } catch (e) {
      debugPrint('获取缓存统计失败: $e');
      return {
        'cacheFileCount': 0,
        'cacheTotalSize': 0,
        'cacheSizeFormatted': '0 B',
        'exportFileCount': 0,
        'exportTotalSize': 0,
        'exportSizeFormatted': '0 B',
        'memoryCacheCount': 0,
      };
    }
  }

  /// 获取用户友好的导出文件列表
  Future<List<Map<String, dynamic>>> getExportFiles() async {
    final exportsDir = await getExportsDirectory();
    final files = await exportsDir.list().toList();
    
    final result = <Map<String, dynamic>>[];
    
    for (var file in files) {
      if (file is File && file.path.toLowerCase().endsWith('.mp4')) {
        final stat = await file.stat();
        result.add({
          'path': file.path,
          'name': path.basename(file.path),
          'size': stat.size,
          'modified': stat.modified,
          'sizeFormatted': _formatFileSize(stat.size),
          'dateFormatted': _formatDate(stat.modified),
        });
      }
    }
    
    // 按修改时间倒序排列
    result.sort((a, b) => b['modified'].compareTo(a['modified']));
    
    return result;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 7) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}