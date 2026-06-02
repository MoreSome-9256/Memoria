/// 推荐查询模板服务，负责把自然语言意图映射成结构化查询。

import '../data/recommendation_query_json_library.dart';
import '../models/vo/semantic_search_models.dart';
import 'semantic_query_parser_service.dart';

class RecommendationQueryTemplateService {
  RecommendationQueryTemplateService._internal();

  static final RecommendationQueryTemplateService _instance =
      RecommendationQueryTemplateService._internal();

  factory RecommendationQueryTemplateService() => _instance;

  final SemanticQueryParserService _parser = SemanticQueryParserService();

  Map<String, dynamic>? resolvePresetJson(
    String rawQuery, {
    DateTime? now,
  }) {
    final preset = RecommendationQueryJsonLibrary.byQuery[rawQuery];
    if (preset == null) {
      return null;
    }
    return _resolveTemplateJson(
      preset.templateJson,
      now: now ?? DateTime.now(),
    );
  }

  SemanticSearchQuery? buildPresetQuery(
    String rawQuery, {
    DateTime? now,
  }) {
    final resolvedJson = resolvePresetJson(rawQuery, now: now);
    if (resolvedJson == null) {
      return null;
    }
    return _parser.buildQueryFromStructuredJson(
      rawQuery: rawQuery,
      jsonObject: resolvedJson,
    );
  }

  Map<String, dynamic> _resolveTemplateJson(
    Map<String, Object?> template, {
    required DateTime now,
  }) {
    final resolved = <String, dynamic>{};
    for (final entry in template.entries) {
      if (entry.key == 'time_ranges' && entry.value is List) {
        resolved[entry.key] = _resolveTimeRanges(
          (entry.value as List).cast<Map<String, Object?>>(),
          now,
        );
      } else {
        resolved[entry.key] = entry.value;
      }
    }
    return resolved;
  }

  List<Map<String, Object?>> _resolveTimeRanges(
    List<Map<String, Object?>> templates,
    DateTime now,
  ) {
    final resolved = <Map<String, Object?>>[];
    for (final item in templates) {
      final template = item['template']?.toString().trim();
      final reason = item['reason']?.toString().trim() ?? '';
      if (template == null || template.isEmpty) {
        resolved.add(item);
        continue;
      }

      final range = switch (template) {
        'current_year' => _yearRange(now.year, reason),
        'previous_year' => _yearRange(now.year - 1, reason),
        'current_month' => _monthRange(now.year, now.month, reason),
        'previous_month' => _monthRange(
            DateTime(now.year, now.month - 1).year,
            DateTime(now.year, now.month - 1).month,
            reason,
          ),
        'same_day_last_year' => _dayRange(
            DateTime(now.year - 1, now.month, now.day),
            reason,
          ),
        'same_day_two_years_ago' => _dayRange(
            DateTime(now.year - 2, now.month, now.day),
            reason,
          ),
        _ => null,
      };

      if (range != null) {
        resolved.add(range);
      }
    }
    return resolved;
  }

  Map<String, Object?> _yearRange(int year, String reason) {
    final start = DateTime(year, 1, 1);
    final end =
        DateTime(year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
    return <String, Object?>{
      'start_time_ms': start.millisecondsSinceEpoch,
      'end_time_ms': end.millisecondsSinceEpoch,
      'reason': reason,
    };
  }

  Map<String, Object?> _monthRange(int year, int month, String reason) {
    final start = DateTime(year, month, 1);
    final end =
        DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
    return <String, Object?>{
      'start_time_ms': start.millisecondsSinceEpoch,
      'end_time_ms': end.millisecondsSinceEpoch,
      'reason': reason,
    };
  }

  Map<String, Object?> _dayRange(DateTime date, String reason) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return <String, Object?>{
      'start_time_ms': start.millisecondsSinceEpoch,
      'end_time_ms': end.millisecondsSinceEpoch,
      'reason': reason,
    };
  }
}
