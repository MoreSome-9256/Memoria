import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/entity/photo_entity.dart';
import '../models/entity/story_entity.dart';
import '../models/vo/photo.dart';
import '../models/vo/story_generation_models.dart';
import '../utils/ocr_policy.dart';
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
      final promptTags = <String>[
        request.title,
        request.subtitle.isEmpty ? '美好时光' : request.subtitle,
      ];
      if (photos.isNotEmpty && (photos.first.aiCaption?.trim().isNotEmpty ?? false)) {
        promptTags.add(photos.first.aiCaption!.trim());
      }

      final musicPrompt = await LLMService().generateMusicPrompt(
        photoTags: promptTags,
        storyTheme: request.title,
      );

      onStatus?.call('正在生成专属配乐');
      preparedMusicPath = await LLMService().generateAndDownloadMusic(
        musicPrompt,
        duration: 12,
      );
      preparedMusicPath ??= await _servePremadeMusic(musicPrompt);
    }

    if (preparedMusicPath != null && preparedMusicPath.isNotEmpty) {
      onStatus?.call('正在分析音乐节拍');
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

    return StoryVideoPreparationResult(
      customMusicPath: preparedMusicPath,
      dynamicBeatData: dynamicBeatData,
      captions: captions,
    );
  }

  Future<List<String>> _generateAutoCaptions({
    required StoryGenerationRequest request,
    required StoryEntity story,
    required List<PhotoEntity> photos,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在撰写视频字幕');
    final narrative = story.content.trim().isEmpty ? request.title : story.content;
    final styleTags = <String>[
      request.subtitle.isEmpty ? '治愈感' : request.subtitle,
      request.targetPlatform,
    ];
    final photoDescriptions = photos.map(_describePhoto).toList(growable: false);

    try {
      return await LLMService().generateVideoCaptionsFromScript(
        narrative: narrative,
        styleTags: styleTags,
        photoDescriptions: photoDescriptions,
      );
    } catch (error) {
      debugPrint('视频字幕生成失败，使用故事文本兜底: $error');
      return _fallbackCaptionsFromStory(story, photos);
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

  List<String> _fallbackCaptionsFromStory(
    StoryEntity story,
    List<PhotoEntity> photos,
  ) {
    final sectionMaps = story.parseToSections(photos);
    final byAssetId = <String, String>{};
    for (final item in sectionMaps) {
      final photo = item['photo'];
      final text = (item['text'] as String? ?? '').trim();
      if (photo is Photo) {
        byAssetId[photo.id] = text;
      }
    }
    return photos
        .map((photo) => byAssetId[photo.assetId] ?? photo.aiCaption?.trim() ?? '')
        .toList(growable: false);
  }

  String _describePhoto(PhotoEntity photo) {
    var desc = photo.aiCaption?.trim();
    if (desc == null || desc.isEmpty) {
      final tags = photo.aiTags ?? const <String>[];
      desc = tags.isNotEmpty ? tags.take(4).join('、') : '未知画面元素';
    }
    final ocrTags = OcrPolicy.effectiveTags(
      photo.ocrTags ?? const <String>[],
      maxTags: 3,
    );
    final ocrText = OcrPolicy.effectiveText(photo.ocrText);
    if (ocrTags.isNotEmpty) {
      desc += '（画面文字：${ocrTags.join('、')}）';
    } else if (ocrText.isNotEmpty) {
      desc += '（画面文字：$ocrText）';
    }
    return desc;
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
    final melancholicScore = melancholicWords.where(lowerPrompt.contains).length;
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
