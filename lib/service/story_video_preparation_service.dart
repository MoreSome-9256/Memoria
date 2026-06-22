// 故事视频准备服务，负责生成视频前的素材整理与时间线构建。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/entity/photo_entity.dart';
import '../models/entity/story_entity.dart';
import '../models/vo/story_generation_models.dart';
import '../utils/ocr_policy.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'llm_service.dart';
import 'music_service.dart';

class StoryVideoPreparationResult {
  const StoryVideoPreparationResult({
    this.customMusicPath,
    this.dynamicBeatData,
    this.captions = const <String>[],
  });

  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final List<String> captions;
}

class StoryVideoPreparationService {
  static const int introSeconds = 3;
  static const int secondsPerPhoto = 3;

  Future<StoryVideoPreparationResult> prepare({
    required StoryGenerationRequest request,
    required StoryEntity story,
    required List<PhotoEntity> photos,
    void Function(String status)? onStatus,
  }) async {
    var preparedMusicPath = request.customMusicPath;
    Map<String, dynamic>? dynamicBeatData;

    if (request.enableAiMusic) {
      onStatus?.call('正在构思 AI 配乐');
      final expectedVideoSeconds = _estimateVideoDurationSeconds(photos.length);
      final promptTags = <String>[
        request.title,
        request.subtitle.isEmpty ? '美好时光' : request.subtitle,
        'target video duration about ${expectedVideoSeconds}s',
      ];
      if (photos.isNotEmpty &&
          (photos.first.aiCaption?.trim().isNotEmpty ?? false)) {
        promptTags.add(photos.first.aiCaption!.trim());
      }

      final musicPrompt = await LLMService().generateMusicPrompt(
        photoTags: promptTags,
        storyTheme: request.title,
      );

      onStatus?.call('正在生成专属配乐');
      preparedMusicPath = await LLMService().generateAndDownloadMusic(
        musicPrompt,
        duration: expectedVideoSeconds,
      );
      preparedMusicPath ??= await _servePremadeMusic(musicPrompt);
    }

    if (preparedMusicPath != null && preparedMusicPath.isNotEmpty) {
      onStatus?.call('正在本地分析音乐节拍与情绪变化');
      dynamicBeatData = await MusicService.analyzeAudio(preparedMusicPath);
    }

    final captions = request.enableAutoCaptions
        ? await _generateAutoCaptions(
            request: request,
            story: story,
            photos: photos,
            onStatus: onStatus,
          )
        : _generateManualCaptions(
            request.manualCaptionsText?.trim() ?? '',
            photos.length,
          );

    // Video captions are part of the story, not transient page state. Persist
    // every entry, including intentionally empty captions.
    story.setVideoCaptions(<String, String>{
      for (var i = 0; i < photos.length; i++)
        photos[i].assetId: i < captions.length ? captions[i] : '',
    });
    ObjectBoxService().store.box<StoryEntity>().put(story);

    return StoryVideoPreparationResult(
      customMusicPath: preparedMusicPath,
      dynamicBeatData: dynamicBeatData,
      captions: captions,
    );
  }

  int _estimateVideoDurationSeconds(int photoCount) {
    // StoryResultPage 会额外插入片头；单轮总长严格按「短片头 + 每张图固定秒数」计算。
    return introSeconds + (photoCount * secondsPerPhoto);
  }

  Future<List<String>> _generateAutoCaptions({
    required StoryGenerationRequest request,
    required StoryEntity story,
    required List<PhotoEntity> photos,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在撰写视频字幕');
    final narrative = story.content.trim().isEmpty
        ? request.title
        : story.content;
    final styleTags = <String>[
      request.subtitle.isEmpty ? '治愈感' : request.subtitle,
      request.targetPlatform,
    ];
    final photoDescriptions = photos
        .map(_describePhoto)
        .toList(growable: false);

    try {
      return await LLMService().generateVideoCaptionsFromScript(
        narrative: narrative,
        styleTags: styleTags,
        photoDescriptions: photoDescriptions,
      );
    } catch (error) {
      debugPrint('视频字幕生成失败，使用故事文本兜底: $error');
      return _fallbackCaptions(photos);
    }
  }

  List<String> _generateManualCaptions(String rawText, int photoCount) {
    final userLines = rawText.isEmpty
        ? const <String>[]
        : rawText
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList(growable: false);
    return List<String>.generate(
      photoCount,
      (index) => index < userLines.length ? userLines[index] : '',
      growable: false,
    );
  }

  List<String> _fallbackCaptions(List<PhotoEntity> photos) {
    // 故事正文是画册文案，长度和语气都不适合作为视频字幕。
    return photos.map(_shortFallbackCaption).toList(growable: false);
  }

  String _shortFallbackCaption(PhotoEntity photo) {
    final source = photo.aiCaption?.trim() ?? '';
    if (source.isNotEmpty) {
      final firstClause = source.split(RegExp(r'[。！？.!?\n]')).first.trim();
      if (firstClause.isNotEmpty) {
        return firstClause.length <= 24
            ? firstClause
            : '${firstClause.substring(0, 23)}…';
      }
    }
    final tags = photo.aiTags ?? const <String>[];
    if (tags.isNotEmpty) return tags.take(3).join(' · ');
    return '这一刻，值得记住';
  }

  String _describePhoto(PhotoEntity photo) {
    final parts = <String>[];
    final caption = photo.aiCaption?.trim();
    if (caption != null && caption.isNotEmpty) {
      parts.add('画面描述：$caption');
    }
    final tags = photo.aiTags ?? const <String>[];
    if (tags.isNotEmpty) {
      parts.add('视觉标签：${tags.take(6).join('、')}');
    }
    final ocrTags = OcrPolicy.effectiveTags(
      photo.ocrTags ?? const <String>[],
      maxTags: 3,
    );
    final ocrText = OcrPolicy.effectiveText(photo.ocrText, maxLength: 48);
    if (ocrTags.isNotEmpty) {
      parts.add('OCR标签：${ocrTags.join('、')}');
    } else if (ocrText.isNotEmpty) {
      parts.add('OCR文字：$ocrText');
    }
    return parts.isEmpty ? '未知画面元素' : parts.join('；');
  }

  Future<String> _servePremadeMusic(String prompt) async {
    final lowerPrompt = prompt.toLowerCase();
    final upbeatWords = <String>[
      'upbeat',
      'happy',
      'energetic',
      'pop',
      'sunny',
      'cheerful',
      'bright',
      'joy',
      'fun',
      'dynamic',
      'party',
    ];
    final cinematicWords = <String>[
      'cinematic',
      'epic',
      'majestic',
      'orchestral',
      'heroic',
      'grand',
      'brass',
      'soaring',
      'powerful',
      'landscape',
    ];
    final melancholicWords = <String>[
      'sad',
      'melancholic',
      'sorrow',
      'tear',
      'heartbreak',
      'grief',
      'depressing',
      'lonely',
      'crying',
      'farewell',
    ];
    final lofiWords = <String>[
      'lo-fi',
      'lofi',
      'chill',
      'cozy',
      'relax',
      'dreamy',
      'gentle',
      'warm',
      'calm',
      'peaceful',
      'nostalgic',
      'anime',
    ];

    final upbeatScore = upbeatWords.where(lowerPrompt.contains).length;
    final cinematicScore = cinematicWords.where(lowerPrompt.contains).length;
    final melancholicScore = melancholicWords
        .where(lowerPrompt.contains)
        .length;
    final lofiScore = lofiWords.where(lowerPrompt.contains).length;

    var assetPath = 'assets/audio/premade/Soft Save Point.mp3';
    var maxScore = 0;
    if (upbeatScore > maxScore) {
      maxScore = upbeatScore;
      assetPath = 'assets/audio/premade/Sunrise Checkpoint.mp3';
    }
    if (cinematicScore > maxScore) {
      maxScore = cinematicScore;
      assetPath = 'assets/audio/premade/Horizons in Motion.mp3';
    }
    if (melancholicScore > maxScore) {
      maxScore = melancholicScore;
      assetPath = 'assets/audio/premade/Faded Save File.mp3';
    }
    if (lofiScore > maxScore) {
      assetPath = 'assets/audio/premade/Soft Save Point.mp3';
    }

    final data = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/ai_bgm_premade_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await tempFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return tempFile.path;
  }
}
