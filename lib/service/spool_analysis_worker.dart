/// 基于 Spool 的纯计算 Worker — 在 foreground isolate 中运行，零 ObjectBox 依赖。
///
/// 读取 manifest → 加载图片 → MobileCLIP 推理 → 标签 → OCR → 人脸检测
/// → 高德逆地理编码 → 写入 result/embedding/progress 到 spool 文件 → 写入 done.marker。
///
/// 以下功能在 main isolate 消费 spool 时完成，不在此处执行：
/// - Face embedding 计算（使用 ONNX / MobileCLIP 模型，从边界框裁剪后）
/// - Caption / VLM 描述生成（后续在 story_generation_orchestrator 中实现）
/// - PhotoEntity / FaceEntity 写入 ObjectBox

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/tag_taxonomy_v2.dart';
import '../utils/ai_score_helper.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'amap_geo_service.dart';
import 'analysis_spool_service.dart';
import 'app_ai_settings_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip_tag_service.dart';
import 'ocr_service.dart';
import 'semantic_matching_service.dart';

/// 计算结果，准备写入 spool。
class _SpoolComputeResult {
  final String photoKey;
  final int photoId;
  final bool didSucceed;
  final List<double> embedding;
  final List<String> tags;
  final String ocrText;
  final List<String> ocrTags;
  final int faceCount;
  final double smileProb;
  final double joyScore;
  final SpoolJunkCandidate? junkCandidate;
  final String? errorMessage;
  final int startedAt;
  final int finishedAt;
  final List<_SpoolWorkerFaceResult> faceResults;

  const _SpoolComputeResult({
    required this.photoKey,
    required this.photoId,
    required this.didSucceed,
    this.embedding = const <double>[],
    this.tags = const <String>[],
    this.ocrText = '',
    this.ocrTags = const <String>[],
    this.faceCount = 0,
    this.smileProb = 0.0,
    this.joyScore = 0.0,
    this.junkCandidate,
    this.errorMessage,
    required this.startedAt,
    required this.finishedAt,
    this.faceResults = const <_SpoolWorkerFaceResult>[],
  });
}

class _SpoolWorkerFaceResult {
  final int faceIndex;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? roll;
  final double? yaw;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double qualityScore;
  final bool isPrimaryFace;

  const _SpoolWorkerFaceResult({
    required this.faceIndex,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.roll,
    this.yaw,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    required this.qualityScore,
    required this.isPrimaryFace,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'faceIndex': faceIndex,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'roll': roll,
    'yaw': yaw,
    'smilingProbability': smilingProbability,
    'leftEyeOpenProbability': leftEyeOpenProbability,
    'rightEyeOpenProbability': rightEyeOpenProbability,
    'qualityScore': qualityScore,
    'isPrimaryFace': isPrimaryFace,
  };
}

/// Spool 纯计算 Worker。
class SpoolAnalysisWorker {
  SpoolAnalysisWorker();

  final MobileClipTagService _tagService = MobileClipTagService();
  final OcrService _ocrService = OcrService();
  final SemanticMatchingService _semanticService = SemanticMatchingService();
  late final AppAiSettings _settings;
  bool _stopRequested = false;

  // Junk filter 原型缓存（build 于 warmUp 中）
  Map<String, List<double>> _junkPrototypes = <String, List<double>>{};
  List<Map<String, Object?>> _junkDefinitions = <Map<String, Object?>>[];

  void requestStop() {
    _stopRequested = true;
  }

  Future<void> run(AnalysisJobManifest manifest) async {
    final spool = AnalysisSpoolService.instance;
    final jobId = manifest.jobId;
    final totalItems = manifest.items.length;
    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    var skipped = 0;

    debugPrint('[spool-worker] ======== 前台 Worker 启动 ========');
    debugPrint('[spool-worker] jobId=$jobId totalItems=$totalItems');

    await spool.baseDir; // 初始化前台 isolate 的 _baseDir
    await spool.ensureJobDirs(jobId);
    final alreadyCompletedKeys = <String>{};
    final existingResultFiles = await spool.listPendingResults(jobId);
    for (final resultFile in existingResultFiles) {
      final result = await spool.readResultFile(resultFile);
      if (result == null) continue;
      alreadyCompletedKeys.add(result.photoKey);
      processed++;
      if (result.isSucceeded) {
        succeeded++;
      } else if (result.isSkipped) {
        skipped++;
      } else {
        failed++;
      }
    }
    if (alreadyCompletedKeys.isNotEmpty) {
      debugPrint('[spool-worker] 检测到已有完整结果 ${alreadyCompletedKeys.length} 个，将从未完成项继续');
    }
    if (processed >= totalItems) {
      await _finishJob(spool, jobId, totalItems, processed, succeeded, failed,
          skipped);
      return;
    }

    final settings = await AppAiSettingsService.instance.load();
    OcrPolicy.setRuntimeEnabled(settings.ocrEnabled);
    _settings = settings;

    debugPrint('[spool-worker] 用户设置: '
        'ocrEnabled=${settings.ocrEnabled} '
        'faceAnalysisEnabled=${settings.faceAnalysisEnabled} '
        'inferenceAccelerator=${settings.inferenceAccelerator} '
        'autoResumeAnalysis=${settings.autoResumeAnalysis}');

    final backend = await MobileClipBackendPreferenceService()
        .getSelectedBackend();
    final enableFaceAnalysis = settings.faceAnalysisEnabled;

    debugPrint('[spool-worker] 选定后端: ${backend.label} '
        'enableFaceAnalysis=$enableFaceAnalysis');

    // 预热引擎
    debugPrint('[spool-worker] 开始预热引擎…');
    await _writeProgress(
      spool, jobId, totalItems, processed, succeeded, failed,
      skipped, '正在预热引擎…',
    );

    final liteRt = MobileClipLiteRtService.withAccelerator(
      settings.inferenceAccelerator,
    );
    final w0 = DateTime.now();
    await liteRt.warmUp();
    debugPrint('[spool-worker] LiteRT 预热耗时: ${DateTime.now().difference(w0).inMilliseconds}ms');
    if (!await _waitIfPausedOrStopped(
      spool, jobId, totalItems, processed, succeeded, failed, skipped,
    )) {
      await _finishJob(spool, jobId, totalItems, processed, succeeded, failed,
          skipped);
      return;
    }
    final w1 = DateTime.now();
    await _tagService.warmUp();
    debugPrint('[spool-worker] TagService 预热耗时: ${DateTime.now().difference(w1).inMilliseconds}ms');
    if (!await _waitIfPausedOrStopped(
      spool, jobId, totalItems, processed, succeeded, failed, skipped,
    )) {
      await _finishJob(spool, jobId, totalItems, processed, succeeded, failed,
          skipped);
      return;
    }
    final w2 = DateTime.now();
    await _warmUpJunkFilter();
    debugPrint('[spool-worker] JunkFilter 预热耗时: ${DateTime.now().difference(w2).inMilliseconds}ms');
    if (!await _waitIfPausedOrStopped(
      spool, jobId, totalItems, processed, succeeded, failed, skipped,
    )) {
      await _finishJob(spool, jobId, totalItems, processed, succeeded, failed,
          skipped);
      return;
    }

    final faceDetector = enableFaceAnalysis
        ? FaceDetector(
            options: FaceDetectorOptions(
              enableClassification: true,
              enableTracking: false,
            ),
          )
        : null;
    debugPrint('[spool-worker] FaceDetector 创建: ${faceDetector != null ? "是" : "否（设置关闭）"}');

    try {
      for (var index = 0; index < manifest.items.length; index++) {
        if (!await _waitIfPausedOrStopped(
          spool, jobId, totalItems, processed, succeeded, failed, skipped,
        )) {
          debugPrint('[spool-worker] ⛔ 收到控制文件停止请求，中断循环 index=$index/$totalItems');
          break;
        }

        if (_stopRequested) {
          debugPrint('[spool-worker] ⛔ 收到停止请求，中断循环 index=$index/$totalItems');
          break;
        }

        final item = manifest.items[index];
        final photoKey = item.photoKey;
        if (alreadyCompletedKeys.contains(photoKey)) {
          debugPrint('[spool-worker] ⏭️ 已有完整结果，跳过第 ${index + 1}/$totalItems 张 photoKey=$photoKey');
          continue;
        }

        debugPrint('[spool-worker] --- 开始处理第 ${index + 1}/$totalItems 张 ---');
        debugPrint('[spool-worker] photoKey=$photoKey path=${item.path} contentUri=${item.contentUri}');
        debugPrint('[spool-worker] GPS: lat=${item.latitude} lng=${item.longitude}');

        await _writeProgress(
          spool, jobId, totalItems, processed, succeeded, failed,
          skipped, '正在分析第 ${index + 1} / $totalItems 张…',
        );

        final startedAt = DateTime.now().millisecondsSinceEpoch;
        _SpoolComputeResult? computeResult;
        try {
          computeResult = await _computeSinglePhoto(
            item: item,
            liteRt: liteRt,
            backend: backend,
            faceDetector: faceDetector,
          );
        } catch (error) {
          debugPrint('[spool-worker] ❌ _computeSinglePhoto 抛出异常: $error');
          debugPrint('[spool-worker] ❌ 堆栈: ${StackTrace.current}');
          computeResult = _SpoolComputeResult(
            photoKey: photoKey,
            photoId: item.photoId ?? 0,
            didSucceed: false,
            errorMessage: error.toString(),
            startedAt: startedAt,
            finishedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }

        final finishedAt = DateTime.now().millisecondsSinceEpoch;
        final elapsed = finishedAt - startedAt;

        if (computeResult.didSucceed) {
          debugPrint('[spool-worker] ✅ 计算成功: '
              'elapsed=${elapsed}ms '
              'tags=${computeResult.tags.length} '
              'ocr=${computeResult.ocrText.isNotEmpty ? "${computeResult.ocrText.length}字" : "无"} '
              'faces=${computeResult.faceResults.length} '
              'junk=${computeResult.junkCandidate != null}');

          // 逆地理编码：有 GPS 坐标时查询高德
          String? province, city, district, locationName, formattedAddress, adcode;
          if (item.latitude != null && item.longitude != null) {
            debugPrint('[spool-worker] 开始逆地理编码 lat=${item.latitude} lng=${item.longitude}');
            final geoStart = DateTime.now();
            final addr = await AmapGeoService.reverseGeocode(
              latitude: item.latitude!,
              longitude: item.longitude!,
            );
            final geoElapsed = DateTime.now().difference(geoStart).inMilliseconds;
            if (addr != null) {
              province = addr.province;
              city = addr.city;
              district = addr.district;
              locationName = addr.locationName;
              formattedAddress = addr.formattedAddress;
              adcode = addr.adcode;
              debugPrint('[spool-worker] ✅ 逆地理编码成功: '
                  'city=$city district=$district '
                  'locationName=$locationName '
                  '耗时=${geoElapsed}ms');
            } else {
              debugPrint('[spool-worker] ⚠️ 逆地理编码返回空 耗时=${geoElapsed}ms');
            }
          } else {
            debugPrint('[spool-worker] ⏭️ 跳过逆地理编码：无 GPS 坐标');
          }

          final result = AnalysisSpoolResult(
            jobId: jobId,
            photoKey: photoKey,
            photoId: computeResult.photoId,
            status: 'succeeded',
            embeddingFile: computeResult.embedding.isNotEmpty
                ? '$photoKey.f32'
                : null,
            embeddingDim: computeResult.embedding.length,
            modelVersion: backend.label,
            startedAt: startedAt,
            finishedAt: finishedAt,
            tags: computeResult.tags,
            aiCaption: '',
            ocrText: computeResult.ocrText,
            ocrTags: computeResult.ocrTags,
            faceCount: computeResult.faceCount,
            smileProb: computeResult.smileProb,
            joyScore: computeResult.joyScore,
            isJunk: computeResult.junkCandidate != null,
            junkCategoryId: computeResult.junkCandidate != null &&
                    computeResult.junkCandidate!.reasons.isNotEmpty
                ? computeResult.junkCandidate!.reasons.first.categoryId
                : null,
            province: province,
            city: city,
            district: district,
            locationName: locationName,
            formattedAddress: formattedAddress,
            adcode: adcode,
          );

          if (computeResult.embedding.isNotEmpty) {
            await spool.writeEmbedding(jobId, photoKey, computeResult.embedding);
            debugPrint('[spool-worker] 📝 Embedding 已写入 spool (dim=${computeResult.embedding.length})');
          } else {
            debugPrint('[spool-worker] ⚠️ 无 embedding 可写入');
          }

          if (computeResult.faceResults.isNotEmpty) {
            await _writeFaceResults(spool, jobId, photoKey,
                computeResult.faceResults);
            debugPrint('[spool-worker] 📝 人脸检测结果已写入 spool (${computeResult.faceResults.length} 张脸)');
          }

          await spool.writeResult(jobId, result);
          debugPrint('[spool-worker] 📝 结果已写入 spool');

          succeeded++;
          debugPrint('[spool-worker] ✅ 第 ${index + 1}/$totalItems 张完成，累计成功=$succeeded');
        } else if (computeResult.errorMessage != null) {
          debugPrint('[spool-worker] ❌ 计算失败: ${computeResult.errorMessage}');
          await spool.writeResult(
            jobId,
            AnalysisSpoolResult(
              jobId: jobId,
              photoKey: photoKey,
              photoId: computeResult.photoId,
              status: 'failed',
              errorMessage: computeResult.errorMessage,
              startedAt: startedAt,
              finishedAt: finishedAt,
            ),
          );
          failed++;
        } else {
          debugPrint('[spool-worker] ⏭️ 跳过（无错误信息）');
          skipped++;
        }

        processed++;
      }
    } finally {
      debugPrint('[spool-worker] finally: 关闭 faceDetector');
      await faceDetector?.close();
    }

    debugPrint('[spool-worker] ======== Worker 运行结束 ========');
    debugPrint('[spool-worker] 总计: processed=$processed succeeded=$succeeded failed=$failed skipped=$skipped');

    await _finishJob(spool, jobId, totalItems, processed, succeeded, failed,
        skipped);
  }

  Future<void> _finishJob(
    AnalysisSpoolService spool,
    String jobId,
    int totalItems,
    int processed,
    int succeeded,
    int failed,
    int skipped,
  ) async {
    await _writeProgress(
      spool, jobId, totalItems, processed, succeeded, failed,
      skipped, processed >= totalItems ? '分析完成' : '已中断',
      status: processed >= totalItems ? 'finished' : 'stopped',
    );
    await spool.writeDoneMarker(jobId);
    debugPrint('[spool-worker] ✅ done.marker 已写入');
  }

  Future<bool> _waitIfPausedOrStopped(
    AnalysisSpoolService spool,
    String jobId,
    int total,
    int processed,
    int succeeded,
    int failed,
    int skipped,
  ) async {
    while (true) {
      final control = await spool.readControl(jobId);
      if (control.stopRequested || _stopRequested) {
        _stopRequested = true;
        await _writeProgress(
          spool, jobId, total, processed, succeeded, failed, skipped,
          '正在结束本轮，等待当前图片收尾',
          status: 'stopping',
        );
        return false;
      }
      if (!control.pauseRequested) {
        return true;
      }
      await _writeProgress(
        spool, jobId, total, processed, succeeded, failed, skipped,
        '后台分析已暂停',
        status: 'paused',
      );
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
  }

  Future<void> _writeProgress(
    AnalysisSpoolService spool,
    String jobId,
    int total,
    int processed,
    int succeeded,
    int failed,
    int skipped,
    String currentStep,
    {
    String? status,
  }) async {
    final resolvedStatus =
        status ?? (_stopRequested ? 'stopped' : processed >= total ? 'finished' : 'running');
    await spool.writeProgress(
      AnalysisProgressSnapshot(
        jobId: jobId,
        status: resolvedStatus,
        total: total,
        processed: processed,
        succeeded: succeeded,
        failed: failed,
        skipped: skipped,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        currentStep: currentStep,
      ),
    );
  }

  Future<void> _writeFaceResults(
    AnalysisSpoolService spool,
    String jobId,
    String photoKey,
    List<_SpoolWorkerFaceResult> faces,
  ) async {
    final json = faces.map((f) => f.toJson()).toList();
    final tmpDir = '${(await spool.baseDir).path}/jobs/$jobId/tmp';
    final key = Uri.encodeComponent(photoKey);
    final tmpFile = File('$tmpDir/${key}_faces.json.tmp');
    final targetFile = File(
      '${(await spool.baseDir).path}/jobs/$jobId/results_pending/${key}_faces.json',
    );
    await tmpFile.writeAsString(
      const JsonEncoder.withIndent(null).convert(json),
      flush: true,
    );
    await tmpFile.rename(targetFile.path);
  }

  // ── Junk Filter 轻量实现 ──

  Future<void> _warmUpJunkFilter() async {
    await _semanticService.warmUp();
    _junkDefinitions = _buildJunkDefinitions();
    for (final def in _junkDefinitions) {
      final id = def['id'] as String;
      final prompts = (def['prototypePrompts'] as List<Object?>).cast<String>();
      _junkPrototypes[id] = await _buildPrototype(prompts);
    }
  }

  Future<List<double>> _buildPrototype(List<String> prompts) async {
    if (prompts.isEmpty) return <double>[];
    var sum = <double>[];
    for (final prompt in prompts) {
      final emb = await _semanticService.embedText(prompt);
      if (emb.isEmpty) continue;
      if (sum.isEmpty) {
        sum = List<double>.from(emb);
      } else {
        for (var i = 0; i < emb.length; i++) {
          sum[i] += emb[i];
        }
      }
    }
    if (sum.isEmpty) return <double>[];
    final len = sum.length;
    var norm = 0.0;
    for (var i = 0; i < len; i++) {
      norm += sum[i] * sum[i];
    }
    norm = math.sqrt(norm);
    if (norm == 0) return <double>[];
    for (var i = 0; i < len; i++) {
      sum[i] /= norm;
    }
    return sum;
  }

  List<Map<String, Object?>> _buildJunkDefinitions() {
    return <Map<String, Object?>>[
      <String, Object?>{
        'id': 'screenshot',
        'label': '截图/界面',
        'description': '聊天截图、支付页、设置页、APP 界面一类的屏幕内容。',
        'prototypePrompts': <String>[
          'a mobile phone screenshot',
          'a screenshot of a chat application',
          'a screenshot of a payment app',
          'a screenshot of a settings page',
          'a screenshot of a shopping app interface',
        ],
        'threshold': 0.24,
        'screenshotBoost': 0.08,
        'ocrBoostThreshold': 24,
        'ocrBoost': 0.02,
      },
      <String, Object?>{
        'id': 'document',
        'label': '文档/表格',
        'description': '纸质文件、课件、报表、白板文字、拍屏文档等。',
        'prototypePrompts': <String>[
          'a photo of a printed document',
          'a scanned paper document',
          'a close-up photo of text on paper',
          'a spreadsheet or report document',
          'a photo of presentation slides on a screen',
        ],
        'threshold': 0.255,
        'ocrBoostThreshold': 40,
        'ocrBoost': 0.035,
      },
      <String, Object?>{
        'id': 'receipt',
        'label': '票据/账单',
        'description': '小票、发票、快递面单、支付凭证、收据等工具型图片。',
        'prototypePrompts': <String>[
          'a photo of a receipt',
          'a bill or invoice document',
          'a shipping label on a package',
          'a payment receipt with text',
        ],
        'threshold': 0.27,
        'ocrBoostThreshold': 28,
        'ocrBoost': 0.03,
      },
      <String, Object?>{
        'id': 'code',
        'label': '二维码/海报码',
        'description': '付款码、二维码海报、条形码、取件码等检索价值较低的图片。',
        'prototypePrompts': <String>[
          'a QR code poster',
          'a payment QR code',
          'a barcode or QR code on a screen',
          'a poster with a large QR code',
        ],
        'threshold': 0.275,
        'ocrBoostThreshold': 12,
        'ocrBoost': 0.015,
      },
      <String, Object?>{
        'id': 'meme',
        'label': '表情包/梗图',
        'description': '聊天表情包、网络梗图、二次创作配文图等重复消费型图片。',
        'prototypePrompts': <String>[
          'a meme image with text overlay',
          'a funny reaction meme or sticker',
          'a social media meme screenshot',
          'a captioned joke image template',
        ],
        'threshold': 0.285,
        'ocrBoostThreshold': 8,
        'ocrBoost': 0.015,
      },
      <String, Object?>{
        'id': 'dark_or_occluded',
        'label': '严重遮挡/过暗',
        'description': '黑屏、口袋误拍、镜头被遮挡、几乎不可辨认的照片。',
        'prototypePrompts': <String>[
          'a nearly black photo',
          'a very dark blurry accidental photo',
          'a photo blocked by a finger',
          'an accidental pocket shot',
          'a heavily shadowed image with no clear subject',
        ],
        'threshold': 0.285,
        'screenshotBoost': 0.03,
      },
      <String, Object?>{
        'id': 'low_value_landmark',
        'label': '低价值地标/路牌',
        'description': '路牌、门牌号、停车位标识、交通指示牌等只有单一信息维度的内容。',
        'prototypePrompts': <String>[
          'a street sign or road sign',
          'a house number or address plate',
          'a parking space sign',
          'a directional signpost',
        ],
        'threshold': 0.27,
        'ocrBoostThreshold': 8,
        'ocrBoost': 0.025,
      },
    ];
  }

  // ── 单张照片分析 ──

  Future<_SpoolComputeResult> _computeSinglePhoto({
    required AnalysisSpoolItem item,
    required MobileClipLiteRtService liteRt,
    required MobileClipBackend backend,
    FaceDetector? faceDetector,
  }) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var phaseLog = <String>[];

    // 1. 加载图片
    final t0 = DateTime.now();
    final input = await _loadImageInput(item);
    final loadMs = DateTime.now().difference(t0).inMilliseconds;
    phaseLog.add('load=${loadMs}ms');

    if (input == null) {
      debugPrint('[spool-worker] ❌ _computeSinglePhoto: 图片加载失败 path=${item.path} uri=${item.contentUri}');
      return _SpoolComputeResult(
        photoKey: item.photoKey,
        photoId: item.photoId ?? 0,
        didSucceed: false,
        errorMessage: '无法加载图片: ${item.path ?? item.contentUri}',
        startedAt: startedAt,
        finishedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    debugPrint('[spool-worker]   图片加载成功: ${input.width}x${input.height} path=${input.file.path}');

    // 2. Embedding（直接 LiteRT，无 ObjectBox 索引）
    final t1 = DateTime.now();
    List<double> embedding;
    try {
      embedding = await liteRt.embedImageBytes(input.mobileClipBytes);
    } catch (error) {
      debugPrint('[spool-worker] ❌ Embedding 计算异常: $error');
      embedding = const <double>[];
    }
    final embedMs = DateTime.now().difference(t1).inMilliseconds;
    phaseLog.add('embed=${embedMs}ms');

    if (embedding.isEmpty) {
      debugPrint('[spool-worker] ❌ Embedding 结果为空，放弃此图');
      return _SpoolComputeResult(
        photoKey: item.photoKey,
        photoId: item.photoId ?? 0,
        didSucceed: false,
        errorMessage: 'Embedding 计算失败',
        startedAt: startedAt,
        finishedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    debugPrint('[spool-worker]   Embedding 成功 dim=${embedding.length}');

    // 3. 标签推理
    final t2 = DateTime.now();
    List<String> tags;
    if (_tagService.isWarmedUp) {
      tags = await compute(
        _spoolComputeTagRetrieval,
        <String, Object?>{
          'embedding': embedding,
          'coarsePrototypes': _tagService.coarsePrototypes,
          'finePrototypes': _tagService.finePrototypes,
          'fineLabelToCoarse': memoriaFineLabelToCoarseId,
          'dimThresholds': <String, double>{
            'subject': 0.165,
            'scene': 0.17,
            'activity': 0.18,
            'atmosphere': 0.19,
            'media': 0.205,
          },
          'coarseThreshold': 0.16,
          'coarseProbThreshold': 0.035,
          'coarseMargin': 0.075,
          'blockedTags': <String>[
            '套路', '未婚妻', '字幕', '房主', '采购员',
          ],
          'coarseTopK': 2,
          'topK': 3,
        },
      );
    } else {
      tags = await _tagService.retrieveTags(embedding);
    }
    final tagMs = DateTime.now().difference(t2).inMilliseconds;
    phaseLog.add('tag=${tagMs}ms');
    final visualTags = _sanitizeVisualTags(tags);
    debugPrint('[spool-worker]   标签推理完成: ${visualTags.length} 个标签 tags=$visualTags');

    SpoolJunkCandidate? junkCandidate;

    // 4. 辅助文件（用于 OCR / 人脸检测）
    final t4 = DateTime.now();
    var compressedBytes = await compute(
      _spoolComputeCompressImage,
      input.file.path,
    );
    if (compressedBytes == null || compressedBytes.isEmpty) {
      compressedBytes = await compute(
        _spoolComputeCompressImageBytes,
        input.mobileClipBytes,
      );
    }
    File analysisFile;
    if (compressedBytes != null && compressedBytes.isNotEmpty) {
      final tempDir = await getTemporaryDirectory();
      final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
      final fileKey = Uri.encodeComponent(item.photoKey);
      final targetPath =
          '${tempDir.path}/temp_mlkit_${fileKey}_$uniqueSuffix.jpg';
      final cf = File(targetPath);
      await cf.writeAsBytes(compressedBytes, flush: true);
      analysisFile = cf;
    } else {
      analysisFile = input.file;
    }
    final compressMs = DateTime.now().difference(t4).inMilliseconds;
    phaseLog.add('compress=${compressMs}ms');
    debugPrint('[spool-worker]   压缩图片完成: ${compressedBytes?.length ?? 0}bytes 耗时=${compressMs}ms');

    // 5. OCR
    final t5 = DateTime.now();
    var ocrResult = OcrResult.empty();
    final aspectRatio = input.height > 0 ? input.width / input.height : 1.0;
    final shouldRunOcr =
        _settings.ocrEnabled &&
        OcrService.shouldRunOcr(visualTags, aspectRatio: aspectRatio);
    if (_settings.ocrEnabled &&
        shouldRunOcr) {
      try {
        ocrResult = await _ocrService.analyzeImageFile(analysisFile);
      } catch (error) {
        debugPrint('[spool-worker]   OCR 跳过：插件处理失败 $error');
      }
    }
    final ocrMs = DateTime.now().difference(t5).inMilliseconds;
    phaseLog.add('ocr=${ocrMs}ms');
    if (_settings.ocrEnabled) {
      debugPrint('[spool-worker]   OCR: enabled=true shouldRun=$shouldRunOcr result=${ocrResult.text.length > 0 ? "${ocrResult.text.length}字" : "无"} tags=${ocrResult.tags} 耗时=${ocrMs}ms');
    } else {
      debugPrint('[spool-worker]   OCR: 跳过（设置关闭）');
    }

    // 6. 垃圾照片过滤
    final t3 = DateTime.now();
    if (item.photoId != null && item.photoId! > 0) {
      final junkResult = await compute(
        _spoolComputeJunkFilter,
        <String, Object?>{
          'embedding': embedding,
          'prototypes': _junkPrototypes,
          'isProbablyScreenshot': false,
          'ocrText': ocrResult.text,
          'definitions': _junkDefinitions,
        },
      );
      final shouldFilter = junkResult['shouldFilter'] as bool? ?? false;
      if (shouldFilter) {
        final rawHits =
            (junkResult['hits'] as List<Object?>?)
                ?.cast<Map<String, Object?>>() ??
            <Map<String, Object?>>[];
        final hits = rawHits
            .map((h) => SpoolJunkHit(
              categoryId: h['categoryId'] as String,
              label: h['label'] as String,
              description: h['description'] as String,
              score: (h['score'] as num).toDouble(),
              threshold: (h['threshold'] as num).toDouble(),
            ))
            .toList(growable: false);
        junkCandidate = SpoolJunkCandidate(
          photoId: item.photoId ?? 0,
          assetId: item.photoKey,
          path: item.path ?? '',
          timestamp: item.modifiedAt,
          reasons: hits,
        );
      }
    }

    final junkMs = DateTime.now().difference(t3).inMilliseconds;
    phaseLog.add('junk=${junkMs}ms');
    if (junkCandidate != null) {
      debugPrint('[spool-worker]   ⚠️ 垃圾照片过滤命中: ${junkCandidate.reasons.map((r) => r.label).join(", ")}');
    }

    // 7. 人脸检测（仅检测，不计算 embedding）
    final t6 = DateTime.now();
    var faceCount = 0;
    var maxSmileProb = 0.0;
    var joyScore = 0.0;
    final faceResults = <_SpoolWorkerFaceResult>[];
    if (faceDetector != null && input.width >= 32 && input.height >= 32) {
      debugPrint('[spool-worker]   开始人脸检测: image=${input.width}x${input.height}');
      try {
        final inputImage = InputImage.fromFile(analysisFile);
        final faces = await faceDetector.processImage(inputImage);
        faceCount = faces.length;
        maxSmileProb = faces.isNotEmpty
            ? faces
                .map((face) => face.smilingProbability ?? 0.0)
                .reduce((a, b) => a > b ? a : b)
            : 0.0;
        joyScore = AIScoreHelper.calculateJoyScore(
          faceCount: faceCount,
          maxSmileProb: maxSmileProb,
          tags: visualTags,
        );
        final primaryIndex = _pickPrimaryFaceIndex(faces);
        debugPrint('[spool-worker]   人脸检测结果: ${faces.length}张脸 maxSmileProb=$maxSmileProb joyScore=$joyScore');
        for (var fi = 0; fi < faces.length; fi++) {
          final face = faces[fi];
          final qualityScore = _estimateFaceQuality(
            face, input.width, input.height,
          );
          faceResults.add(_SpoolWorkerFaceResult(
            faceIndex: fi,
            left: face.boundingBox.left,
            top: face.boundingBox.top,
            right: face.boundingBox.right,
            bottom: face.boundingBox.bottom,
            roll: face.headEulerAngleZ,
            yaw: face.headEulerAngleY,
            smilingProbability: face.smilingProbability,
            leftEyeOpenProbability: face.leftEyeOpenProbability,
            rightEyeOpenProbability: face.rightEyeOpenProbability,
            qualityScore: qualityScore,
            isPrimaryFace: fi == primaryIndex,
          ));
        }
      } catch (error) {
        debugPrint('[spool-worker]   人脸检测跳过：插件处理失败 $error');
      }
    } else if (faceDetector != null) {
      debugPrint('[spool-worker]   人脸检测跳过: 图片太小 ${input.width}x${input.height} (<32)');
    } else {
      debugPrint('[spool-worker]   人脸检测跳过: 设置关闭');
    }
    final faceMs = DateTime.now().difference(t6).inMilliseconds;
    phaseLog.add('face=${faceMs}ms');

    // 清理临时文件
    if (analysisFile.path != input.file.path &&
        await analysisFile.exists()) {
      try { await analysisFile.delete(); } catch (_) {}
    }

    final totalMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    debugPrint('[spool-worker]   🏁 _computeSinglePhoto 完成: ${phaseLog.join(" ")} total=${totalMs}ms');

    return _SpoolComputeResult(
      photoKey: item.photoKey,
      photoId: item.photoId ?? 0,
      didSucceed: true,
      embedding: embedding,
      tags: visualTags,
      ocrText: ocrResult.text,
      ocrTags: ocrResult.tags,
      faceCount: faceCount,
      smileProb: maxSmileProb,
      joyScore: joyScore,
      startedAt: startedAt,
      finishedAt: DateTime.now().millisecondsSinceEpoch,
      junkCandidate: junkCandidate,
      faceResults: faceResults,
    );
  }

  // ── 图片输入加载 ──

  Future<_SpoolInputImage?> _loadImageInput(AnalysisSpoolItem item) async {
    final path = item.path;
    Uint8List bytes;
    File file;
    var width = item.width;
    var height = item.height;

    if (path != null && path.isNotEmpty) {
      file = File(path);
      if (!await file.exists()) return null;
      final asset = await AssetEntity.fromId(item.photoKey);
      if (asset != null) {
        width = width > 0 ? width : asset.width;
        height = height > 0 ? height : asset.height;
        try {
          final thumb = await asset.thumbnailDataWithSize(
            const ThumbnailSize.square(384),
          );
          if (thumb != null && thumb.isNotEmpty) {
            return _SpoolInputImage(
              file: file,
              mobileClipBytes: thumb,
              width: width,
              height: height,
            );
          }
        } catch (_) {}
      }
      bytes = await file.readAsBytes();
    } else {
      return null;
    }

    if (width <= 0 || height <= 0) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        width = decoded.width;
        height = decoded.height;
      }
    }

    return _SpoolInputImage(
      file: file,
      mobileClipBytes: bytes,
      width: width,
      height: height,
    );
  }

  int _pickPrimaryFaceIndex(List<Face> faces) {
    var bestIndex = 0;
    var bestScore = -double.infinity;
    for (var i = 0; i < faces.length; i++) {
      final rect = faces[i].boundingBox;
      final score = rect.width * rect.height +
          (faces[i].smilingProbability ?? 0.0) * 1000;
      if (score > bestScore) { bestScore = score; bestIndex = i; }
    }
    return bestIndex;
  }

  double _estimateFaceQuality(Face face, int photoWidth, int photoHeight) {
    final areaRatio =
        (face.boundingBox.width * face.boundingBox.height) /
        math.max(1, photoWidth * photoHeight);
    final smile = face.smilingProbability ?? 0.0;
    final eyes = ((face.leftEyeOpenProbability ?? 0.0) +
        (face.rightEyeOpenProbability ?? 0.0)) / 2;
    final yawPenalty = (face.headEulerAngleY?.abs() ?? 0.0) / 90.0;
    final rollPenalty = (face.headEulerAngleZ?.abs() ?? 0.0) / 90.0;
    final raw = areaRatio * 2.5 + smile * 0.1 + eyes * 0.1;
    final penalty = (yawPenalty + rollPenalty) * 0.15;
    return (raw - penalty).clamp(0.0, 1.0);
  }

  List<String> _sanitizeVisualTags(List<String> source, {int maxTags = 5}) {
    const blocked = <String>{
      'Screenshot', 'Cool', 'Glasses', 'Goggles', 'Selfie', '截图', '自拍',
    };
    final sanitized = <String>[];
    for (final tag in source) {
      final normalized = TagSanitizer.sanitizeVisualTag(tag);
      if (normalized == null || sanitized.contains(normalized)) continue;
      if (blocked.contains(normalized)) continue;
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(normalized)) continue;
      sanitized.add(normalized);
      if (sanitized.length >= maxTags) break;
    }
    return TagSanitizer.sanitizeVisualTags(sanitized, maxTags: maxTags);
  }
}

// ── Junk filter 数据类（轻量，无 ObjectBox 依赖） ──

class SpoolJunkHit {
  final String categoryId;
  final String label;
  final String description;
  final double score;
  final double threshold;

  const SpoolJunkHit({
    required this.categoryId,
    required this.label,
    required this.description,
    required this.score,
    required this.threshold,
  });
}

class SpoolJunkCandidate {
  final int photoId;
  final String assetId;
  final String path;
  final int timestamp;
  final List<SpoolJunkHit> reasons;

  const SpoolJunkCandidate({
    required this.photoId,
    required this.assetId,
    required this.path,
    required this.timestamp,
    required this.reasons,
  });
}

/// 照片适配器 — 让 manifest item 能传给需要 PhotoEntity 接口的服务。
/// 注意：本 worker 已不再使用 MobileClipEmbeddingService，但保留适配器以备扩展。
class _ManifestPhotoAdapter {
  _ManifestPhotoAdapter(this._item);
  final AnalysisSpoolItem _item;

  int get id => _item.photoId ?? 0;
  String get path => _item.path ?? '';
  String get assetId => _item.photoKey;
  int get timestamp => _item.modifiedAt;
  int get eventId => 0;
}

class _SpoolInputImage {
  final File file;
  final Uint8List mobileClipBytes;
  final int width;
  final int height;
  const _SpoolInputImage({
    required this.file,
    required this.mobileClipBytes,
    required this.width,
    required this.height,
  });
}

// ── 后台 isolate 计算函数（与 ai_service_photo_processor.dart 逻辑对应，零 ObjectBox） ──

Map<String, Object?> _spoolComputeJunkFilter(Map<String, Object?> params) {
  final embedding = (params['embedding'] as List<Object?>).cast<double>();
  final prototypes = (params['prototypes'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, (v as List<Object?>).cast<double>()));
  final isProbablyScreenshot = params['isProbablyScreenshot'] as bool? ?? false;
  final ocrText = params['ocrText'] as String? ?? '';
  final definitions =
      (params['definitions'] as List<Object?>).cast<Map<String, Object?>>();

  final hits = <Map<String, Object?>>[];
  for (final def in definitions) {
    final id = def['id'] as String;
    final prototype = prototypes[id];
    if (prototype == null || prototype.length != embedding.length) continue;
    var score = _spoolCosineSimilarity(embedding, prototype);
    final screenshotBoost = (def['screenshotBoost'] as num?)?.toDouble() ?? 0.0;
    if (screenshotBoost > 0 && isProbablyScreenshot) score += screenshotBoost;
    final ocrBoost = (def['ocrBoost'] as num?)?.toDouble() ?? 0.0;
    final ocrThreshold = (def['ocrBoostThreshold'] as num?)?.toInt() ?? 9999;
    if (ocrBoost > 0 && ocrText.length >= ocrThreshold) score += ocrBoost;
    score = score.clamp(-1.0, 1.0);
    final threshold = (def['threshold'] as num).toDouble();
    if (score >= threshold) {
      hits.add(<String, Object?>{
        'categoryId': id,
        'label': def['label'] as String,
        'description': def['description'] as String,
        'score': score,
        'threshold': threshold,
      });
    }
  }
  hits.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  return <String, Object?>{'shouldFilter': hits.isNotEmpty, 'hits': hits};
}

List<String> _spoolComputeTagRetrieval(Map<String, Object?> params) {
  final embedding = (params['embedding'] as List<Object?>).cast<double>();
  final coarsePrototypes = (params['coarsePrototypes'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, (v as List<Object?>).cast<double>()));
  final finePrototypes = (params['finePrototypes'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, (v as List<Object?>).cast<double>()));
  final fineLabelToCoarse = (params['fineLabelToCoarse'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, v as String));
  final dimThresholds = (params['dimThresholds'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, (v as num).toDouble()));
  final coarseThreshold = (params['coarseThreshold'] as num?)?.toDouble() ?? 0.16;
  final coarseProbThreshold = (params['coarseProbThreshold'] as num?)?.toDouble() ?? 0.035;
  final coarseMargin = (params['coarseMargin'] as num?)?.toDouble() ?? 0.075;
  final blockedTags = (params['blockedTags'] as List<Object?>?)?.cast<String>() ?? <String>[];
  final coarseTopK = (params['coarseTopK'] as num?)?.toInt() ?? 2;
  final topK = (params['topK'] as num?)?.toInt() ?? 3;

  final coarseScored = <Map<String, Object?>>[];
  for (final entry in coarsePrototypes.entries) {
    final score = _spoolCosineSimilarity(embedding, entry.value);
    if (score >= coarseThreshold) {
      coarseScored.add(<String, Object?>{'coarseId': entry.key, 'score': score});
    }
  }
  coarseScored.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));

  final scores = coarseScored.map((e) => (e['score'] as num).toDouble()).toList();
  final maxScore = scores.isEmpty ? 0.0 : scores.reduce((a, b) => a > b ? a : b);
  final expScores = scores.map((s) => _spoolFastExp(s - maxScore)).toList();
  final expSum = expScores.isEmpty ? 1.0 : expScores.reduce((a, b) => a + b);
  for (var i = 0; i < coarseScored.length; i++) {
    coarseScored[i] = <String, Object?>{
      ...coarseScored[i], 'probability': expScores[i] / expSum,
    };
  }
  coarseScored.retainWhere((e) => (e['probability'] as num).toDouble() >= coarseProbThreshold);
  coarseScored.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  final topScore = coarseScored.isNotEmpty
      ? (coarseScored.first['score'] as num).toDouble()
      : 0.0;
  coarseScored.retainWhere(
    (e) => topScore - (e['score'] as num).toDouble() <= coarseMargin,
  );
  final coarseSelected = coarseScored.take(coarseTopK).toList();
  if (coarseSelected.isEmpty) return <String>['照片', '其他'];

  final selectedCoarseIds = coarseSelected.map((e) => e['coarseId'] as String).toSet();
  final coarseProbById = <String, double>{
    for (final e in coarseSelected)
      e['coarseId'] as String: (e['probability'] as num).toDouble(),
  };

  final scored = <_SpoolTagCandidate>[];
  for (final entry in finePrototypes.entries) {
    final label = entry.key;
    if (blockedTags.contains(label)) continue;
    final coarseId = fineLabelToCoarse[label];
    if (coarseId == null || !selectedCoarseIds.contains(coarseId)) continue;
    final score = _spoolCosineSimilarity(embedding, entry.value);
    final coarseProb = coarseProbById[coarseId] ?? 0.0;
    final weightedScore = score * (0.5 + 0.5 * coarseProb);
    final dimThreshold = switch (coarseId) {
      'subject' => dimThresholds['subject'] ?? 0.165,
      'scene' => dimThresholds['scene'] ?? 0.17,
      'activity' => dimThresholds['activity'] ?? 0.18,
      'atmosphere' => dimThresholds['atmosphere'] ?? 0.19,
      'media' => dimThresholds['media'] ?? 0.205,
      _ => 0.2,
    };
    if (score < dimThreshold) continue;
    scored.add(_SpoolTagCandidate(label: label, score: score, weightedScore: weightedScore));
  }
  if (scored.isEmpty) return <String>['照片', '其他'];
  scored.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
  final selected = <String>[];
  final selectedSet = <String>{};
  for (final coarseId in selectedCoarseIds) {
    final best = scored.where((c) => fineLabelToCoarse[c.label] == coarseId).toList();
    if (best.isNotEmpty && !selectedSet.contains(best.first.label)) {
      selected.add(best.first.label);
      selectedSet.add(best.first.label);
    }
  }
  for (final candidate in scored) {
    if (selected.length >= topK) break;
    if (selectedSet.contains(candidate.label)) continue;
    selected.add(candidate.label);
    selectedSet.add(candidate.label);
  }
  return selected.isEmpty ? <String>['照片', '其他'] : selected;
}

List<int>? _spoolComputeCompressImage(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    return _spoolCompressImageBytes(file.readAsBytesSync());
  } catch (_) { return null; }
}

List<int>? _spoolComputeCompressImageBytes(Uint8List bytes) {
  try {
    return _spoolCompressImageBytes(bytes);
  } catch (_) {
    return null;
  }
}

List<int>? _spoolCompressImageBytes(List<int> bytes) {
  final decoded = img.decodeImage(Uint8List.fromList(bytes));
  if (decoded == null) return null;
  final baked = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    baked,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.linear,
  );
  return img.encodeJpg(resized, quality: 80);
}

double _spoolCosineSimilarity(List<double> a, List<double> b) {
  final len = a.length;
  if (len == 0 || len != b.length) return 0.0;
  var dot = 0.0;
  for (var i = 0; i < len; i++) { dot += a[i] * b[i]; }
  return dot.clamp(-1.0, 1.0);
}

double _spoolFastExp(double x) => math.exp(x);

class _SpoolTagCandidate {
  final String label;
  final double score;
  final double weightedScore;
  const _SpoolTagCandidate({
    required this.label,
    required this.score,
    required this.weightedScore,
  });
}

/// JSON 编码（用于 _writeFaceResults 中序列化 List）
const _spoolJsonEncoder = JsonEncoder.withIndent(null);
