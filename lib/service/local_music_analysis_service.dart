// Local music analysis service for beat and mood-shift extraction.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalMusicAnalysisService {
  static const int _sampleRate = 16000;
  static const int _frameSize = 1024;
  static const int _hopSize = 512;

  Future<Map<String, dynamic>?> analyze(String filePath) async {
    final source = File(filePath);
    if (!source.existsSync()) {
      debugPrint('本地音乐分析失败：文件不存在 $filePath');
      return null;
    }

    final wavPath = await _decodeToMonoWav(filePath);
    if (wavPath == null) {
      return null;
    }

    try {
      final samples = await _readPcm16Wav(wavPath);
      if (samples.length < _sampleRate) {
        debugPrint('本地音乐分析失败：音频太短');
        return null;
      }

      final envelope = _buildOnsetEnvelope(samples);
      final bpm = _estimateBpm(envelope);
      final beats = _buildBeatTimeline(envelope, bpm, samples.length);
      final emotions = _buildEmotionTimeline(samples);

      return <String, dynamic>{
        'source': 'local_ffmpeg_dart',
        'analyzer_version': 1,
        'file_name': p.basename(filePath),
        'sample_rate': _sampleRate,
        'duration_ms': (samples.length / _sampleRate * 1000).round(),
        'bpm': bpm,
        'data': beats,
        'emotion': emotions,
        'llm_workflow': _buildWorkflowSummary(bpm, beats, emotions),
      };
    } catch (error) {
      debugPrint('本地音乐分析异常: $error');
      return null;
    } finally {
      unawaited(File(wavPath).delete().catchError((_) => File(wavPath)));
    }
  }

  Future<String?> _decodeToMonoWav(String filePath) async {
    final dir = await getTemporaryDirectory();
    final outputPath =
        '${dir.path}/memoria_audio_${DateTime.now().microsecondsSinceEpoch}.wav';
    final command =
        '-y -i ${_quote(filePath)} -vn -ac 1 -ar $_sampleRate -sample_fmt s16 ${_quote(outputPath)}';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      debugPrint('FFmpeg 音频解码失败: $logs');
      return null;
    }
    return outputPath;
  }

  Future<Float32List> _readPcm16Wav(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Unsupported WAV container');
    }

    var offset = 12;
    int? dataOffset;
    int? dataSize;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (dataOffset == null || dataSize == null) {
      throw const FormatException('WAV data chunk not found');
    }

    final sampleCount = dataSize ~/ 2;
    final samples = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  List<double> _buildOnsetEnvelope(Float32List samples) {
    final energies = <double>[];
    var previous = 0.0;
    for (
      var start = 0;
      start + _frameSize <= samples.length;
      start += _hopSize
    ) {
      var energy = 0.0;
      for (var i = 0; i < _frameSize; i++) {
        final sample = samples[start + i];
        energy += sample * sample;
      }
      energy = math.sqrt(energy / _frameSize);
      energies.add(math.max(0, energy - previous));
      previous = energy;
    }
    return _normalize(energies);
  }

  double _estimateBpm(List<double> envelope) {
    if (envelope.length < 8) {
      return 120.0;
    }
    final framesPerSecond = _sampleRate / _hopSize;
    final minLag = (framesPerSecond * 60 / 180).round();
    final maxLag = (framesPerSecond * 60 / 60).round();
    var bestLag = minLag;
    var bestScore = double.negativeInfinity;

    for (var lag = minLag; lag <= maxLag; lag++) {
      var score = 0.0;
      for (var i = lag; i < envelope.length; i++) {
        score += envelope[i] * envelope[i - lag];
      }
      final bpm = 60 * framesPerSecond / lag;
      final tempoPrior = math.exp(-math.pow((bpm - 110) / 55, 2));
      score *= 0.75 + tempoPrior * 0.25;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }

    final bpm = 60 * framesPerSecond / bestLag;
    return double.parse(bpm.clamp(60.0, 180.0).toStringAsFixed(1));
  }

  List<Map<String, dynamic>> _buildBeatTimeline(
    List<double> envelope,
    double bpm,
    int sampleCount,
  ) {
    final durationMs = sampleCount / _sampleRate * 1000;
    final intervalMs = 60000 / bpm;
    final beats = <Map<String, dynamic>>[];
    var ms = _findFirstStrongOnsetMs(envelope).toDouble();
    while (ms < durationMs) {
      final frame = (ms / 1000 * _sampleRate / _hopSize).round();
      final energy = frame >= 0 && frame < envelope.length
          ? envelope[frame]
          : 0.0;
      beats.add(<String, dynamic>{
        'ms': ms.round(),
        'energy': double.parse(energy.clamp(0.05, 1.0).toStringAsFixed(3)),
      });
      ms += intervalMs;
    }
    if (beats.isEmpty) {
      beats.add(<String, dynamic>{'ms': 0, 'energy': 0.3});
    }
    return beats;
  }

  int _findFirstStrongOnsetMs(List<double> envelope) {
    for (var i = 0; i < envelope.length; i++) {
      if (envelope[i] > 0.55) {
        return (i * _hopSize / _sampleRate * 1000).round();
      }
    }
    return 0;
  }

  Map<String, dynamic> _buildEmotionTimeline(Float32List samples) {
    final windowSize = _sampleRate * 4;
    final hopSize = _sampleRate * 2;
    final segments = <Map<String, dynamic>>[];

    for (var start = 0; start < samples.length; start += hopSize) {
      final end = math.min(start + windowSize, samples.length);
      if (end - start < _sampleRate) {
        break;
      }
      var rms = 0.0;
      var zcr = 0;
      for (var i = start; i < end; i++) {
        final sample = samples[i];
        rms += sample * sample;
        if (i > start && (samples[i - 1] >= 0) != (sample >= 0)) {
          zcr++;
        }
      }
      rms = math.sqrt(rms / (end - start));
      final zcrRate = zcr / (end - start);
      final arousal = (rms * 7.5).clamp(0.0, 1.0);
      final valence = (0.52 + (zcrRate - 0.06) * 2.4 + (arousal - 0.5) * 0.25)
          .clamp(0.0, 1.0);
      segments.add(<String, dynamic>{
        'start_ms': (start / _sampleRate * 1000).round(),
        'end_ms': (end / _sampleRate * 1000).round(),
        'arousal': double.parse(arousal.toStringAsFixed(3)),
        'valence': double.parse(valence.toStringAsFixed(3)),
        'label': _emotionLabel(arousal, valence),
      });
    }

    final summary = _summarizeEmotion(segments);
    return <String, dynamic>{'summary': summary, 'segments': segments};
  }

  String _summarizeEmotion(List<Map<String, dynamic>> segments) {
    if (segments.isEmpty) {
      return '情绪变化不明显';
    }
    final labels = segments.map((item) => item['label'].toString()).toList();
    final first = labels.first;
    final last = labels.last;
    final uniqueCount = labels.toSet().length;
    if (uniqueCount <= 1) {
      return '整体保持$first';
    }
    return '从$first逐步变化到$last，中间有${uniqueCount - 2}段情绪转折';
  }

  String _emotionLabel(double arousal, double valence) {
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

  List<double> _normalize(List<double> values) {
    if (values.isEmpty) {
      return values;
    }
    final sorted = List<double>.from(values)..sort();
    final pivot =
        sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    if (pivot <= 0) {
      return List<double>.filled(values.length, 0);
    }
    return values.map((value) => (value / pivot).clamp(0.0, 1.0)).toList();
  }

  Map<String, dynamic> _buildWorkflowSummary(
    double bpm,
    List<Map<String, dynamic>> beats,
    Map<String, dynamic> emotions,
  ) {
    final segments = (emotions['segments'] as List?) ?? const <dynamic>[];
    return <String, dynamic>{
      'stage': 'on_device_music_analysis',
      'next_stage': 'cloud_llm_story_generation',
      'prompt_summary':
          '端侧音乐分析：BPM ${bpm.toStringAsFixed(1)}，共 ${beats.length} 个节拍点；${emotions['summary']}。请让剧本分镜、转场密度和旁白情绪贴合音乐节奏。',
      'editing_hints': <String>[
        bpm >= 125 ? '适合快节奏卡点和短句旁白' : '适合舒展转场和较长旁白',
        if (segments.isNotEmpty)
          '情绪段落：${segments.take(4).map((item) => '${item['start_ms']}ms-${item['label']}').join('；')}',
      ],
    };
  }

  String _quote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
