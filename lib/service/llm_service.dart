import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/entity/event_entity.dart';

part 'llm_service_titles.dart';
part 'llm_service_completion.dart';
part 'llm_service_story_music.dart';

/// LLM 服务 - 通过 OpenAI 兼容第三方中转站生成内容
class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal({
    String? apiKey,
    String? baseUrl,
    String? apiPath,
    String? modelName,
    String? replicateApiToken,
    Dio? dio,
  }) : _apiKey = apiKey ?? _defaultApiKey,
       _baseUrl = baseUrl ?? _defaultBaseUrl,
       _apiPath = apiPath ?? _defaultApiPath,
       _modelName = modelName ?? _defaultModelName,
       _replicateApiToken = replicateApiToken ?? _defaultReplicateApiToken,
       _visionModelName = _defaultVisionModelName.isEmpty
           ? (modelName ?? _defaultModelName)
           : _defaultVisionModelName,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 20),
               contentType: 'application/json',
             ),
           );

  static const Set<String> _blockedTitleWords = <String>{
    '采购员',
    '房主',
    '房东',
    '未婚妻',
    '未婚夫',
    '套路',
    '老婆',
    '丈夫',
    '情人',
  };

  factory LLMService.forTest({
    required String apiKey,
    required String baseUrl,
    String apiPath = '/chat/completions',
    String modelName = 'deepseek-ai/DeepSeek-V3.2',
    String? replicateApiToken,
    Dio? dio,
  }) {
    return LLMService._internal(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      modelName: modelName,
      replicateApiToken: replicateApiToken,
      dio: dio,
    );
  }

  // 通过 --dart-define 配置，避免硬编码凭证
  static const String _defaultApiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );
  static const String _defaultBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: 'https://api-inference.modelscope.cn/v1',
  );
  static const String _defaultApiPath = String.fromEnvironment(
    'LLM_API_PATH',
    defaultValue: '/chat/completions',
  );
  static const String _defaultModelName = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-ai/DeepSeek-V3.2',
  );
  static const String _defaultVisionModelName = String.fromEnvironment(
    'LLM_VISION_MODEL',
    defaultValue: '',
  );
  static const String _defaultReplicateApiToken = String.fromEnvironment(
    'REPLICATE_API_TOKEN',
    defaultValue: '',
  );

  final String _apiKey;
  final String _baseUrl;
  final String _apiPath;
  final String _modelName;
  final String _replicateApiToken;
  final String _visionModelName;
  final Dio _dio;
  static const String _defaultTextSystemPrompt =
      '你是一个中文摄影故事与标题助手。只能基于输入信息生成，不要编造未提供事实。';

  bool get isApiKeyConfigured =>
      _apiKey.trim().isNotEmpty && _baseUrl.trim().isNotEmpty;

  bool get isVisionApiConfigured => isApiKeyConfigured;
}
