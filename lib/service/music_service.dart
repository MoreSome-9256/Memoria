// 音乐服务，统一提供端侧音乐节拍和情绪分析入口。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:music_feature_analyzer/music_feature_analyzer.dart';
import 'package:path/path.dart' as p;

import 'local_music_analysis_service.dart';

class MusicService {
  static final LocalMusicAnalysisService _localAnalyzer =
      LocalMusicAnalysisService();
  static bool _isFeatureAnalyzerReady = false;

  static Future<Map<String, dynamic>?> analyzeAudio(String filePath) async {
    try {
      debugPrint('🎵 本地分析音频: $filePath');
      final result =
          await _analyzeWithMusicFeatureAnalyzer(filePath) ??
          await _localAnalyzer.analyze(filePath);
      if (result == null) {
        debugPrint('❌ 本地音乐分析失败');
        return null;
      }
      debugPrint(
        '✅ 本地音乐分析完成: BPM=${result['bpm']}, beats=${(result['data'] as List?)?.length ?? 0}',
      );
      return result;
    } catch (error) {
      debugPrint('❌ 本地音乐分析异常: $error');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _analyzeWithMusicFeatureAnalyzer(
    String filePath,
  ) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }

    try {
      if (!_isFeatureAnalyzerReady) {
        _isFeatureAnalyzerReady = await MusicFeatureAnalyzer.initialize();
      }
      if (!_isFeatureAnalyzerReady) {
        return null;
      }

      final metadata = await MusicFeatureAnalyzer.metadata(filePath);
      final fileName = p.basename(filePath);
      final song =
          metadata ??
          SongModel(
            id: filePath,
            title: p.basenameWithoutExtension(fileName),
            artist: '',
            album: '',
            duration: 0,
            filePath: filePath,
          );

      final features = await MusicFeatureAnalyzer.analyzeSong(song);
      if (features == null || features.tempoBpm <= 0) {
        return null;
      }

      final durationMs = song.duration > 0 ? song.duration : 0;
      final beats = _buildBeatTimelineFromBpm(
        bpm: features.tempoBpm,
        durationMs: durationMs,
        beatStrength: features.beatStrength,
      );
      final emotion = _buildFeatureEmotion(features, durationMs);

      return <String, dynamic>{
        'source': 'music_feature_analyzer',
        'analyzer_version': '1.0.3',
        'file_name': fileName,
        'duration_ms': durationMs,
        'bpm': double.parse(features.tempoBpm.toStringAsFixed(1)),
        'data': beats,
        'emotion': emotion,
        'features': <String, dynamic>{
          'tempo': features.tempo,
          'beat': features.beat,
          'beat_strength': features.beatStrength,
          'energy': features.energy,
          'overall_energy': features.overallEnergy,
          'danceability': features.danceability,
          'mood': features.mood,
          'mood_tags': features.moodTags,
          'valence': features.valence,
          'arousal': features.arousal,
          'genre': features.estimatedGenre,
          'instruments': features.instruments,
          'yamnet_instruments': features.yamnetInstruments,
          'has_vocals': features.hasVocals,
          'vocals': features.vocals,
          'confidence': features.confidence,
        },
        'llm_workflow': _buildWorkflowSummary(
          bpm: features.tempoBpm,
          beats: beats,
          emotion: emotion,
          features: features,
        ),
      };
    } catch (error) {
      debugPrint('music_feature_analyzer 分析失败，回退到内置本地分析: $error');
      return null;
    }
  }

  static List<Map<String, dynamic>> _buildBeatTimelineFromBpm({
    required double bpm,
    required int durationMs,
    required double beatStrength,
  }) {
    final intervalMs = bpm > 0 ? 60000 / bpm : 500.0;
    final effectiveDuration = durationMs > 0 ? durationMs : intervalMs.round();
    final beats = <Map<String, dynamic>>[];
    var ms = 0.0;
    while (ms < effectiveDuration) {
      beats.add(<String, dynamic>{
        'ms': ms.round(),
        'energy': double.parse(
          beatStrength.clamp(0.05, 1.0).toStringAsFixed(3),
        ),
      });
      ms += intervalMs;
    }
    return beats.isEmpty
        ? <Map<String, dynamic>>[
            <String, dynamic>{'ms': 0, 'energy': beatStrength.clamp(0.05, 1.0)},
          ]
        : beats;
  }

  static Map<String, dynamic> _buildFeatureEmotion(
    ExtractedSongFeatures features,
    int durationMs,
  ) {
    final label = _emotionLabel(features.arousal, features.valence);
    return <String, dynamic>{
      'summary':
          '整体$label，mood=${features.mood}，valence=${features.valence.toStringAsFixed(2)}，arousal=${features.arousal.toStringAsFixed(2)}',
      'segments': <Map<String, dynamic>>[
        <String, dynamic>{
          'start_ms': 0,
          'end_ms': durationMs > 0 ? durationMs : 0,
          'arousal': double.parse(features.arousal.toStringAsFixed(3)),
          'valence': double.parse(features.valence.toStringAsFixed(3)),
          'danceability': double.parse(
            features.danceability.toStringAsFixed(3),
          ),
          'energy': double.parse(features.overallEnergy.toStringAsFixed(3)),
          'label': label,
        },
      ],
    };
  }

  static String _emotionLabel(double arousal, double valence) {
    if (arousal >= 0.62 && valence >= 0.55) {
      return '明亮有动感';
    }
    if (arousal >= 0.62 && valence < 0.55) {
      return '紧张有冲击';
    }
    if (arousal < 0.38 && valence >= 0.55) {
      return '温柔舒缓';
    }
    if (arousal < 0.38 && valence < 0.55) {
      return '安静低回';
    }
    return valence >= 0.55 ? '平稳温暖' : '克制沉静';
  }

  static Map<String, dynamic> _buildWorkflowSummary({
    required double bpm,
    required List<Map<String, dynamic>> beats,
    required Map<String, dynamic> emotion,
    required ExtractedSongFeatures features,
  }) {
    return <String, dynamic>{
      'stage': 'on_device_music_feature_analysis',
      'next_stage': 'cloud_llm_story_generation',
      'prompt_summary':
          '端侧 music_feature_analyzer 分析：BPM ${bpm.toStringAsFixed(1)}，共 ${beats.length} 个节拍点；${emotion['summary']}；danceability=${features.danceability.toStringAsFixed(2)}，genre=${features.estimatedGenre}。请让剧本分镜、转场密度和旁白情绪贴合音乐节奏。',
      'editing_hints': <String>[
        bpm >= 125 ? '适合快节奏卡点和短句旁白' : '适合舒展转场和较长旁白',
        features.danceability >= 0.65 ? '可以提高镜头切换密度' : '保持镜头停留和情绪留白',
        '音乐情绪：${features.mood} / ${features.moodTags.take(3).join('、')}',
      ],
    };
  }
}
