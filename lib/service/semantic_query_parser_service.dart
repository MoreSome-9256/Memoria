import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/vo/semantic_search_models.dart';
import 'llm_service.dart';
import 'semantic_matching_service.dart';

part 'semantic_query_parser_constants.dart';
part 'semantic_query_parser_short_route.dart';
part 'semantic_query_parser_local_fallback.dart';
part 'semantic_query_parser_llm.dart';
part 'semantic_query_parser_models.dart';

class SemanticQueryParserService {
  SemanticQueryParserService._internal();

  static final SemanticQueryParserService _instance =
      SemanticQueryParserService._internal();

  factory SemanticQueryParserService() => _instance;

  final LLMService _llmService = LLMService();
  final SemanticMatchingService _semanticService = SemanticMatchingService();

  Future<SemanticSearchQuery> parseQuery(
    String rawQuery, {
    Set<String> locationDictionary = const <String>{},
  }) async {
    final normalized = rawQuery.trim();
    if (normalized.isEmpty) {
      return SemanticSearchQuery.empty(rawQuery);
    }

    final shortQuery = await _buildShortSemanticQueryIfNeeded(normalized);
    if (shortQuery != null) {
      return shortQuery;
    }

    final localFallback = _buildLocalFallbackQuery(
      normalized,
      locationDictionary,
    );

    if (_isMetadataOnlyQuery(normalized, localFallback)) {
      return localFallback;
    }

    if (!_llmService.isApiKeyConfigured) {
      return localFallback.copyWith(
        llmConfigured: false,
        notes: _appendNote(localFallback.notes, _noteLlmMissing),
      );
    }

    try {
      final llmQuery = await _parseWithLlm(normalized, locationDictionary);
      return _mergeQueries(llmQuery, localFallback);
    } catch (error) {
      debugPrint('SemanticQueryParserService parse with llm failed: $error');
      return localFallback.copyWith(
        llmConfigured: true,
        notes: _appendNote(localFallback.notes, _noteLlmFailed),
      );
    }
  }
}
