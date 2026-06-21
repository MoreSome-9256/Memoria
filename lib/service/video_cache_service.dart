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

  // 内存缓存：sessionId -> 视频路径
  final Map<String, String> _sessionCache = {};

  /// 生成视频缓存指纹（基于完整导出参数的 sha256）
  /// 保证相同图片、文本、音频和特效参数会命中同一个视频文件。
  String buildVideoCacheKey({
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
    final normalizedSections = sections
        .map(
          (section) => <String, dynamic>{
            'mediaFingerprint':
                section['photo']?['fingerprint'] as String? ?? '',
            'mediaKind': section['photo']?['mediaKind'] as String? ?? '',
            'dateTaken': section['photo']?['dateTaken'],
            'width': section['photo']?['width'],
            'height': section['photo']?['height'],
            'text': section['text'] as String? ?? '',
          },
        )
        .toList(growable: false);

    final fingerprintData = <String, dynamic>{
      // Bump whenever the render timeline semantics change.
      'renderTimelineVersion': 2,
      'title': title,
      'subtitle': subtitle,
      'sections': normalizedSections,
      'customMusicPath': customMusicPath ?? '__default__',
      'dynamicBeatData': dynamicBeatData ?? const <String, dynamic>{},
      'targetPlatform': targetPlatform,
      'isHorizontal': isHorizontal,
      'currentTextStyle': currentTextStyle,
      'textYPosition': textYPosition,
      'textSize': textSize,
      'textBlurIntensity': textBlurIntensity,
      'shakeIntensity': shakeIntensity,
      'shakeFrequency': shakeFrequency,
      'glitchIntensity': glitchIntensity,
      'enableFlash': enableFlash,
      'useVignette': useVignette,
      'useGrain': useGrain,
      'useCameraFrame': useCameraFrame,
      'useGlowRing': useGlowRing,
      'useCloudBorder': useCloudBorder,
    };

    final jsonString = jsonEncode(fingerprintData);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 获取视频缓存目录。
  ///
  /// 这是生成视频的主缓存位置，由设置页缓存管理统一清理。
  /// 不写入系统相册 / Movies；需要给用户在 iOS 文件 App 中查看时，
  /// 再复制一份到 Documents/StoryExports。
  Future<Directory> getCacheDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(path.join(supportDir.path, _cacheSubdir));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// 获取 iOS 文件 App 可见的私有导出目录。
  ///
  /// StoryExports 位于 App 私有 Documents 下；配合 Info.plist 的
  /// UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace 暴露给“文件”App。
  /// 这里保存的是缓存视频的展示副本，缓存源文件仍由 getCacheDirectory() 管理。
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
    String? cacheKey,
  }) async {
    final sessionId = cacheKey ?? _legacySessionId(sections);

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
    String? cacheKey,
  }) async {
    final sessionId = cacheKey ?? _legacySessionId(sections);

    final cacheDir = await getCacheDirectory();
    final cachedPath = path.join(cacheDir.path, '$sessionId.mp4');
    final cachedFile = File(cachedPath);

    if (await cachedFile.exists()) {
      _sessionCache[sessionId] = cachedPath;
      return cachedPath;
    }

    // 复制到缓存目录
    await File(videoPath).copy(cachedPath);

    // 更新内存缓存
    _sessionCache[sessionId] = cachedPath;

    return cachedPath;
  }

  /// 确保 iOS 文件 App 可见目录中存在当前视频。
  ///
  /// 注意：这是复制，不是移动。用户如果删掉 StoryExports 下的展示副本，
  /// 只要缓存源文件还在，下次打开文件 App 前会自动补齐。
  Future<String> ensureExportedVideoAvailable(
    String sourcePath, {
    String? cacheKey,
    String? customName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('缓存视频不存在，无法复制到 StoryExports', sourcePath);
    }

    final exportsDir = await getExportsDirectory();
    final fileName =
        customName ?? _exportFileNameFor(sourcePath, cacheKey: cacheKey);
    final destPath = path.join(exportsDir.path, fileName);

    final destFile = File(destPath);
    if (await destFile.exists()) {
      return destPath;
    }

    await sourceFile.copy(destPath);

    // 清理旧的导出文件（保留最近10个）
    await _cleanOldExports(exportsDir, keepCount: 10);

    return destPath;
  }

  /// 兼容旧调用名；实际行为是复制到 StoryExports，不移动源缓存。
  Future<String> moveToExportsDirectory(
    String sourcePath, {
    String? customName,
  }) {
    return ensureExportedVideoAvailable(sourcePath, customName: customName);
  }

  String _exportFileNameFor(String sourcePath, {String? cacheKey}) {
    final normalizedKey = cacheKey?.trim();
    if (normalizedKey != null && normalizedKey.isNotEmpty) {
      return 'Story_$normalizedKey.mp4';
    }

    final sourceName = path.basenameWithoutExtension(sourcePath).trim();
    if (sourceName.isNotEmpty) {
      final name = sourceName.startsWith('Story_')
          ? sourceName
          : 'Story_$sourceName';
      return '$name.mp4';
    }

    return 'Story_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  String _legacySessionId(List<Map<String, dynamic>> sections) {
    final legacyData = {
      'sections': sections
          .map(
            (section) => <String, dynamic>{
              'mediaFingerprint':
                  section['photo']?['fingerprint'] as String? ?? '',
              'mediaKind': section['photo']?['mediaKind'] as String? ?? '',
              'dateTaken': section['photo']?['dateTaken'],
              'width': section['photo']?['width'],
              'height': section['photo']?['height'],
              'text': section['text'] as String? ?? '',
            },
          )
          .toList(growable: false),
    };
    final jsonString = jsonEncode(legacyData);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString();
  }

  /// 清理旧的导出文件
  Future<void> _cleanOldExports(
    Directory exportsDir, {
    int keepCount = 10,
  }) async {
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
              fileName.startsWith('mux_temp_') ||
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
