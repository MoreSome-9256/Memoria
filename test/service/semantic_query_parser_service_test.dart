import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/semantic_query_parser_service.dart';

void main() {
  test('structured plan keeps measurable attribute constraints', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '开心的多人合照',
      jsonObject: <String, dynamic>{
        'query_type': 'attribute',
        'time_ranges': const <Object>[],
        'local_time_windows': const <Object>[],
        'locations': const <Object>[],
        'coarse_tags': const <Object>[],
        'tag_strictness': 'optional',
        'positive_semantics': const <Map<String, Object>>[
          <String, Object>{
            'text': 'a joyful group photo with smiling people',
            'weight': 1.0,
          },
        ],
        'recall_semantics': const <Map<String, Object>>[
          <String, Object>{
            'text': 'friends or family smiling together',
            'weight': 1.0,
          },
        ],
        'negative_semantics': const <Object>[],
        'attributes': const <String, Object>{
          'min_face_count': 2,
          'min_smile_probability': 0.45,
          'media_kinds': <String>['image', 'dynamicImage'],
        },
        'estimated_result_count': const <String, Object>{
          'min': 1,
          'max': 50,
          'confidence': 0.8,
        },
      },
    );

    expect(query.attributes.minFaceCount, 2);
    expect(query.attributes.minSmileProbability, 0.45);
    expect(query.attributes.mediaKinds, <String>['image', 'dynamicImage']);
  });

  test('unqualified summer becomes a recurring cross-year constraint', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '夏天的海边',
      jsonObject: <String, dynamic>{
        'query_type': 'concrete',
        'time_ranges': <Map<String, Object>>[
          <String, Object>{
            'start': '2026-06-01T00:00:00+08:00',
            'end': '2026-08-31T23:59:59+08:00',
          },
        ],
        'local_time_windows': const <Object>[],
        'locations': const <Object>[],
        'coarse_tags': const <Object>[],
        'tag_strictness': 'optional',
        'positive_semantics': const <Map<String, Object>>[
          <String, Object>{'text': 'a summer seaside photo', 'weight': 1.0},
        ],
        'recall_semantics': const <Map<String, Object>>[
          <String, Object>{'text': 'a sunny coastal scene', 'weight': 1.0},
        ],
        'negative_semantics': const <Object>[],
        'attributes': const <String, Object>{},
        'estimated_result_count': const <String, Object>{
          'min': 1,
          'max': 50,
          'confidence': 0.8,
        },
      },
    );

    expect(query.timeRanges, hasLength(1));
    expect(query.timeRanges.single.recurringStartMonth, 6);
    expect(query.timeRanges.single.recurringEndMonth, 10);
    expect(query.timeRanges.single.hasDateBoundary, isFalse);
  });

  test('structured visual semantics must be English MobileCLIP prompts', () {
    expect(
      () => SemanticQueryParserService().buildQueryFromStructuredJson(
        rawQuery: '夏天的海边',
        jsonObject: <String, dynamic>{
          'query_type': 'concrete',
          'time_ranges': const <Object>[],
          'local_time_windows': const <Object>[],
          'locations': const <Object>[],
          'coarse_tags': const <Object>[],
          'tag_strictness': 'optional',
          'positive_semantics': const <Map<String, Object>>[
            <String, Object>{'text': '海边照片', 'weight': 1.0},
          ],
          'recall_semantics': const <Map<String, Object>>[
            <String, Object>{'text': 'a sunny coastal scene', 'weight': 1.0},
          ],
          'negative_semantics': const <Object>[],
          'attributes': const <String, Object>{},
          'estimated_result_count': const <String, Object>{
            'min': 1,
            'max': 50,
            'confidence': 0.8,
          },
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('positive_semantics'),
        ),
      ),
    );
  });

  test('QueryPlan v1 preserves Chinese geo and mechanical filters', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '周末夏天在青岛海边',
      jsonObject: <String, dynamic>{
        'version': 1,
        'raw_query': '周末夏天在青岛海边',
        'embedding_queries_en': <String>[
          'summer beach travel photo',
          'seaside scenery',
        ],
        'objectbox_filters': <String, dynamic>{
          'absolute_date_ranges': const <Object>[],
          'annual_day_ranges': const <Map<String, int>>[
            <String, int>{'start_day_of_year': 152, 'end_day_of_year': 243},
          ],
          'minute_of_day_ranges': const <Object>[],
          'weekdays': const <int>[6, 7],
          'geo': const <Map<String, dynamic>>[
            <String, dynamic>{
              'raw_name': '青岛',
              'normalized_names': <String>['青岛', '青岛市'],
              'amap_query_keywords': <String>['青岛', '青岛市'],
              'kind_hint': 'city',
              'strictness': 'broad',
            },
          ],
        },
        'soft_filters': const <String, dynamic>{
          'visual_terms_en': <String>['a coastal city in summer'],
        },
        'negative_filters': const <String, dynamic>{
          'visual_terms_en': <String>['a lake without the sea'],
        },
      },
    );

    expect(query.locations.single.text, '青岛');
    expect(query.locations.single.aliases, contains('青岛市'));
    expect(query.weekdays, <int>[6, 7]);
    expect(query.timeRanges.single.annualStartDay, 152);
    expect(query.positiveSemanticTexts, contains('summer beach travel photo'));
    expect(query.positiveSemantics.every((item) => !item.containsCjk), isTrue);
  });
}
