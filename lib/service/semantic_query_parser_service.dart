// 语义查询解析主服务。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/vo/semantic_search_models.dart';
import 'llm_service.dart';

part 'semantic_query_parser_llm.dart';
part 'semantic_query_parser_models.dart';

class SemanticQueryParserService {
  SemanticQueryParserService._internal();

  static final SemanticQueryParserService _instance =
      SemanticQueryParserService._internal();

  factory SemanticQueryParserService() => _instance;

  final LLMService _llmService = LLMService();

  SemanticSearchQuery buildQueryFromStructuredJson({
    required String rawQuery,
    required Map<String, dynamic> jsonObject,
  }) {
    final primary = _buildStructuredQueryFromJsonObject(
      rawQuery: rawQuery,
      jsonObject: jsonObject,
      usedLlm: false,
      llmConfigured: true,
      parserSource: 'preset_json',
      baseNotes: '预置结构化查询',
    );
    return primary;
  }

  Future<SemanticSearchQuery> parseQuery(String rawQuery) async {
    final normalized = rawQuery.trim();
    if (normalized.isEmpty) {
      return SemanticSearchQuery.empty(rawQuery);
    }

    if (!_llmService.isApiKeyConfigured) {
      throw StateError('LLM 未配置，无法执行自然语言检索。请先配置云端代理或 LLM 服务。');
    }

    try {
      final llmQuery = await _parseWithLlm(normalized);
      return llmQuery;
    } catch (error) {
      debugPrint('SemanticQueryParserService parse with llm failed: $error');
      throw StateError('LLM 查询解析失败，无法执行自然语言检索: $error');
    }
  }
}
