// LLM 服务主入口，封装标题、文案、音乐提示词和对话请求。

import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import '../models/entity/event_entity.dart';
import 'api_proxy_config.dart';
import 'api_proxy_service.dart';

part 'llm_service_titles.dart';
part 'llm_service_completion.dart';
part 'llm_service_story_music.dart';

/// LLM service for generating stories, titles, captions, and music prompts
/// through OpenAI-compatible API providers.
class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal({String? baseUrl, String? apiPath, String? modelName})
    : _baseUrl = baseUrl ?? _resolvedDefaultBaseUrl,
      _apiPath = apiPath ?? _defaultApiPath,
      _modelName = modelName ?? _defaultModelName,
      _visionModelName = _defaultVisionModelName.isEmpty
          ? (modelName ?? _defaultModelName)
          : _defaultVisionModelName;

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
    required String baseUrl,
    String apiPath = '/chat/completions',
    String modelName = 'deepseek-ai/DeepSeek-V3.2',
  }) {
    return LLMService._internal(
      baseUrl: baseUrl,
      apiPath: apiPath,
      modelName: modelName,
    );
  }

  // Configure cloud access through API_PROXY_BASE_URL and Cognito.
  static const String _defaultBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: '',
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
  static String get _resolvedDefaultBaseUrl => _defaultBaseUrl.trim().isNotEmpty
      ? _defaultBaseUrl
      : ApiProxyConfig.join('/v1/llm');

  final String _baseUrl;
  final String _apiPath;
  final String _modelName;
  final String _visionModelName;
  static const String _defaultTextSystemPrompt =
      '你是一个中文摄影故事与标题助手。只能基于输入信息生成，不要编造未提供事实。';

  bool get isApiKeyConfigured =>
      _baseUrl.trim().isNotEmpty && ApiProxyConfig.isEnabled;

  bool get isVisionApiConfigured => isApiKeyConfigured;
}
