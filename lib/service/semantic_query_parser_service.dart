import 'dart:convert';

import '../data/tag_taxonomy_v2.dart';
import '../models/vo/semantic_search_models.dart';
import 'llm_service.dart';

class SemanticQueryParserService {
  SemanticQueryParserService._internal();

  static final SemanticQueryParserService _instance =
      SemanticQueryParserService._internal();

  factory SemanticQueryParserService() => _instance;

  static const Set<String> _semanticStopWords = <String>{
    '照片',
    '图片',
    '相片',
    '相册',
    '回忆',
    '那次',
    '那年',
    '那天',
    '时候',
    '一下',
    '看看',
    '想看',
    '给我',
    '帮我',
    '找找',
    '搜索',
    '搜一下',
  };

  Future<SemanticSearchQuery> parseQuery(
    String rawQuery, {
    required Set<String> locationDictionary,
  }) async {
    final llmConfigured = LLMService().isApiKeyConfigured;
    final local = _buildLocalFallback(
      rawQuery,
      locationDictionary: locationDictionary,
      llmConfigured: llmConfigured,
    );
    if (!llmConfigured) {
      return local;
    }

    try {
      final llm = await _parseWithLlm(
        rawQuery,
        locationDictionary: locationDictionary,
      );
      if (llm == null) {
        return local;
      }
      return _mergeQueries(rawQuery, local, llm);
    } catch (error) {
      return local;
    }
  }

  SemanticSearchQuery _buildLocalFallback(
    String rawQuery, {
    required Set<String> locationDictionary,
    required bool llmConfigured,
  }) {
    var remaining = rawQuery.trim();
    final locations = <String>[];
    final strippedLocationMap = <String, String>{};
    for (final location in locationDictionary) {
      strippedLocationMap[_normalizeLocation(location)] = location;
    }

    final sortedLocations = strippedLocationMap.keys.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final normalized in sortedLocations) {
      if (normalized.length < 2) {
        continue;
      }
      if (remaining.contains(normalized)) {
        final location = strippedLocationMap[normalized];
        if (location != null && !locations.contains(location)) {
          locations.add(location);
        }
        remaining = remaining.replaceAll(normalized, ' ');
      }
    }

    final timeRange = _extractTimeRange(rawQuery);
    final includeTags = <String>[];
    final excludeTags = <String>[];
    for (final label in memoriaMasterLabels) {
      if (rawQuery.contains('不要$label') ||
          rawQuery.contains('排除$label') ||
          rawQuery.contains('不看$label') ||
          rawQuery.contains('别要$label')) {
        excludeTags.add(label);
        remaining = remaining.replaceAll(label, ' ');
      } else if (rawQuery.contains(label)) {
        includeTags.add(label);
        remaining = remaining.replaceAll(label, ' ');
      }
    }

    final allowScreenshots =
        _wantsScreenshotLikeContent(rawQuery) &&
        !_wantsExcludeScreenshotLikeContent(rawQuery);

    remaining = _stripSemanticStopWords(remaining);
    final query = SemanticSearchQuery(
      rawQuery: rawQuery,
      semanticQuery: remaining.isEmpty ? rawQuery.trim() : remaining,
      negativeSemanticQuery: excludeTags.join(' '),
      includeTags: includeTags,
      excludeTags: excludeTags,
      includeLocations: locations,
      excludeLocations: const <String>[],
      includeOcrTerms: _extractQuotedTerms(rawQuery),
      excludeOcrTerms: const <String>[],
      allowScreenshots: allowScreenshots,
      startTimeMs: timeRange.$1,
      endTimeMs: timeRange.$2,
      usedLlm: false,
      llmConfigured: llmConfigured,
      parserSource: llmConfigured ? 'local_fallback' : 'local_only',
      debugJson: '',
    );
    return query.copyWith(debugJson: _toDebugJson(query));
  }

  Future<SemanticSearchQuery?> _parseWithLlm(
    String rawQuery, {
    required Set<String> locationDictionary,
  }) async {
    final prompt = '''
请将下面这句中文图片搜索请求解析为 JSON，用于本地相册搜索。

当前日期：${DateTime.now().toIso8601String().split('T').first}

你可以参考的标签词表（优先使用这些中文标签）：
${memoriaMasterLabels.join('、')}

你可以参考的地点词表（若用户明确提到，尽量从中选择）：
${locationDictionary.take(120).join('、')}

输出 JSON，字段严格如下：
{
  "semantic_query": "正向语义描述，适合做向量检索的短语",
  "negative_semantic_query": "不想要的内容，适合做负向向量扣分；没有则为空字符串",
  "include_tags": ["希望出现的标签"],
  "exclude_tags": ["希望排除的标签"],
  "include_locations": ["希望命中的地点"],
  "exclude_locations": ["希望排除的地点"],
  "include_ocr_terms": ["希望 OCR 文本命中的关键词"],
  "exclude_ocr_terms": ["希望 OCR 文本排除的关键词"],
  "allow_screenshots": false,
  "start_date": "2025-01-01 或 null",
  "end_date": "2025-12-31 或 null"
}

规则：
1. 只输出 JSON，不要 Markdown，不要解释。
2. 如果用户说“不要截图/不要文档/不要课件”，allow_screenshots 必须为 false。
3. 如果用户明确要找截图、文档、屏幕、聊天记录，allow_screenshots 设为 true。
4. “去年/前年/今年/上个月/最近”请换算成合理日期范围。
5. include_tags / exclude_tags 尽量使用上方词表中的标签；没有明确标签就留空数组。
6. semantic_query 保留最核心的画面意图，不要照抄整句口语。

用户原始请求：
$rawQuery
''';

    final text = await LLMService().completeText(
      prompt: prompt,
      systemPrompt:
          '你是一个严格输出 JSON 的中文相册搜索查询解析器。只能输出合法 JSON，绝不输出解释。',
    );
    if (text == null || text.trim().isEmpty) {
      return null;
    }

    final decoded = _decodeJson(text);
    if (decoded == null) {
      return null;
    }

    final query = SemanticSearchQuery(
      rawQuery: rawQuery,
      semanticQuery: _readString(decoded, 'semantic_query'),
      negativeSemanticQuery: _readString(decoded, 'negative_semantic_query'),
      includeTags: _readStringList(decoded, 'include_tags'),
      excludeTags: _readStringList(decoded, 'exclude_tags'),
      includeLocations: _readStringList(decoded, 'include_locations'),
      excludeLocations: _readStringList(decoded, 'exclude_locations'),
      includeOcrTerms: _readStringList(decoded, 'include_ocr_terms'),
      excludeOcrTerms: _readStringList(decoded, 'exclude_ocr_terms'),
      allowScreenshots: _readBool(decoded, 'allow_screenshots'),
      startTimeMs: _readDateMs(decoded, 'start_date'),
      endTimeMs: _readDateMs(decoded, 'end_date', endOfDay: true),
      usedLlm: true,
      llmConfigured: true,
      parserSource: 'deepseek',
      debugJson: '',
    );
    return query.copyWith(debugJson: _toDebugJson(query));
  }

  SemanticSearchQuery _mergeQueries(
    String rawQuery,
    SemanticSearchQuery local,
    SemanticSearchQuery llm,
  ) {
    final semanticQuery = llm.semanticQuery.trim().isNotEmpty
        ? llm.semanticQuery.trim()
        : local.semanticQuery;
    final negativeQuery = llm.negativeSemanticQuery.trim().isNotEmpty
        ? llm.negativeSemanticQuery.trim()
        : local.negativeSemanticQuery;
    final forceExcludeScreenshots = _wantsExcludeScreenshotLikeContent(rawQuery);
    final merged = local.copyWith(
      semanticQuery: semanticQuery,
      negativeSemanticQuery: negativeQuery,
      includeTags: _mergeList(local.includeTags, llm.includeTags),
      excludeTags: _mergeList(local.excludeTags, llm.excludeTags),
      includeLocations: _mergeList(local.includeLocations, llm.includeLocations),
      excludeLocations: _mergeList(local.excludeLocations, llm.excludeLocations),
      includeOcrTerms: _mergeList(local.includeOcrTerms, llm.includeOcrTerms),
      excludeOcrTerms: _mergeList(local.excludeOcrTerms, llm.excludeOcrTerms),
      allowScreenshots: forceExcludeScreenshots
          ? false
          : (llm.allowScreenshots || local.allowScreenshots),
      startTimeMs: llm.startTimeMs ?? local.startTimeMs,
      endTimeMs: llm.endTimeMs ?? local.endTimeMs,
      usedLlm: true,
      llmConfigured: true,
      parserSource: llm.parserSource,
      debugJson: '',
    );
    return merged.copyWith(debugJson: _toDebugJson(merged));
  }

  List<String> _mergeList(List<String> left, List<String> right) {
    final result = <String>[];
    for (final value in <String>[...left, ...right]) {
      final normalized = value.trim();
      if (normalized.isEmpty || result.contains(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    return result;
  }

  (int?, int?) _extractTimeRange(String rawQuery) {
    final yearMatch = RegExp(r'(20\d{2})').firstMatch(rawQuery);
    if (yearMatch != null) {
      final year = int.tryParse(yearMatch.group(0)!);
      if (year != null) {
        return (_startOfYearMs(year), _endOfYearMs(year));
      }
    }

    final now = DateTime.now();
    if (rawQuery.contains('去年')) {
      return (_startOfYearMs(now.year - 1), _endOfYearMs(now.year - 1));
    }
    if (rawQuery.contains('前年')) {
      return (_startOfYearMs(now.year - 2), _endOfYearMs(now.year - 2));
    }
    if (rawQuery.contains('今年')) {
      return (_startOfYearMs(now.year), _endOfYearMs(now.year));
    }
    if (rawQuery.contains('上个月')) {
      final month = now.month == 1 ? 12 : now.month - 1;
      final year = now.month == 1 ? now.year - 1 : now.year;
      return (_startOfMonthMs(year, month), _endOfMonthMs(year, month));
    }
    if (rawQuery.contains('最近') || rawQuery.contains('近一个月')) {
      final start = now.subtract(const Duration(days: 30));
      return (DateTime(start.year, start.month, start.day).millisecondsSinceEpoch,
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
              .millisecondsSinceEpoch);
    }
    return (null, null);
  }

  String _stripSemanticStopWords(String value) {
    var cleaned = value;
    for (final stopWord in _semanticStopWords) {
      cleaned = cleaned.replaceAll(stopWord, ' ');
    }
    cleaned = cleaned.replaceAll(RegExp(r'[的在把给帮我想看找出搜一下]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  List<String> _extractQuotedTerms(String rawQuery) {
    final matches = RegExp(r'["“](.*?)["”]').allMatches(rawQuery);
    final terms = <String>[];
    for (final match in matches) {
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty && !terms.contains(value)) {
        terms.add(value);
      }
    }
    return terms;
  }

  String _normalizeLocation(String value) {
    return value.replaceAll(RegExp(r'[省市自治区县盟旗]'), '').trim();
  }

  bool _wantsScreenshotLikeContent(String rawQuery) {
    final query = rawQuery.trim();
    return query.contains('截图') ||
        query.contains('屏幕') ||
        query.contains('文档') ||
        query.contains('课件') ||
        query.contains('聊天记录');
  }

  bool _wantsExcludeScreenshotLikeContent(String rawQuery) {
    final query = rawQuery.trim();
    return query.contains('不要截图') ||
        query.contains('别要截图') ||
        query.contains('排除截图') ||
        query.contains('不要屏幕') ||
        query.contains('排除屏幕') ||
        query.contains('不要文档') ||
        query.contains('排除文档') ||
        query.contains('不要课件') ||
        query.contains('排除课件');
  }

  String _toDebugJson(SemanticSearchQuery query) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'raw_query': query.rawQuery,
      'semantic_query': query.semanticQuery,
      'negative_semantic_query': query.negativeSemanticQuery,
      'include_tags': query.includeTags,
      'exclude_tags': query.excludeTags,
      'include_locations': query.includeLocations,
      'exclude_locations': query.excludeLocations,
      'include_ocr_terms': query.includeOcrTerms,
      'exclude_ocr_terms': query.excludeOcrTerms,
      'allow_screenshots': query.allowScreenshots,
      'start_time_ms': query.startTimeMs,
      'end_time_ms': query.endTimeMs,
      'used_llm': query.usedLlm,
      'llm_configured': query.llmConfigured,
      'parser_source': query.parserSource,
    });
  }

  Map<String, dynamic>? _decodeJson(String text) {
    final cleanText = text
        .replaceAll(RegExp(r'```json|```', caseSensitive: false), '')
        .trim();
    try {
      final decoded = jsonDecode(cleanText);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleanText);
      if (match == null) {
        return null;
      }
      final body = match.group(0);
      if (body == null) {
        return null;
      }
      try {
        final decoded = jsonDecode(body);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
  }

  String _readString(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value == null ? '' : value.toString().trim();
  }

  List<String> _readStringList(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! List) {
      return const <String>[];
    }
    final result = <String>[];
    for (final item in value) {
      final normalized = item.toString().trim();
      if (normalized.isEmpty || result.contains(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    return result;
  }

  bool _readBool(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is bool) {
      return value;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  int? _readDateMs(
    Map<String, dynamic> map,
    String key, {
    bool endOfDay = false,
  }) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return null;
    }
    final normalized = endOfDay
        ? DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
            23,
            59,
            59,
            999,
          )
        : DateTime(parsed.year, parsed.month, parsed.day);
    return normalized.millisecondsSinceEpoch;
  }

  int _startOfYearMs(int year) => DateTime(year, 1, 1).millisecondsSinceEpoch;

  int _endOfYearMs(int year) =>
      DateTime(year, 12, 31, 23, 59, 59, 999).millisecondsSinceEpoch;

  int _startOfMonthMs(int year, int month) =>
      DateTime(year, month, 1).millisecondsSinceEpoch;

  int _endOfMonthMs(int year, int month) =>
      DateTime(year, month + 1, 0, 23, 59, 59, 999).millisecondsSinceEpoch;
}
