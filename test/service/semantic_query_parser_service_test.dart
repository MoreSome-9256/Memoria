import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/vo/semantic_search_models.dart';
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

  test('LLM-provided spring uses annual MM-DD dates', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '春天的花',
      jsonObject: <String, dynamic>{
        'query_type': 'concrete',
        'time_ranges': <Map<String, Object>>[
          <String, Object>{
            'annual_start_date': '03-01',
            'annual_end_date': '05-31',
            'reason': 'spring in any year',
          },
        ],
        'local_time_windows': const <Object>[],
        'locations': const <Object>[],
        'coarse_tags': const <Map<String, Object>>[
          <String, Object>{
            'id': 'flowers_plants',
            'label_en': 'flowers and plants',
            'confidence': 0.9,
          },
        ],
        'tag_strictness': 'prefer',
        'positive_semantics': const <Map<String, Object>>[
          <String, Object>{
            'text': 'spring flowers and blossoms',
            'weight': 1.0,
          },
        ],
        'recall_semantics': const <Map<String, Object>>[
          <String, Object>{'text': 'flower blossoms in spring', 'weight': 1.0},
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
    expect(query.timeRanges.single.annualStartMonth, 3);
    expect(query.timeRanges.single.annualStartDayOfMonth, 1);
    expect(query.timeRanges.single.annualEndMonth, 5);
    expect(query.timeRanges.single.annualEndDayOfMonth, 31);
    expect(query.timeRanges.single.hasDateBoundary, isFalse);
  });

  test('month-only query stays metadata-only with annual MM-DD dates', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '5月的照片',
      jsonObject: <String, dynamic>{
        'query_type': 'metadata',
        'time_ranges': const <Map<String, Object>>[
          <String, Object>{
            'annual_start_date': '05-01',
            'annual_end_date': '05-31',
            'reason': 'May in any year',
          },
        ],
        'local_time_windows': const <Object>[],
        'locations': const <Object>[],
        'coarse_tags': const <Object>[],
        'tag_strictness': 'optional',
        'positive_semantics': const <Object>[],
        'recall_semantics': const <Object>[],
        'negative_semantics': const <Object>[],
        'attributes': const <String, Object>{},
        'estimated_result_count': const <String, Object>{
          'min': 1,
          'max': 240,
          'confidence': 0.8,
        },
      },
    );

    expect(query.queryType, SemanticSearchQueryType.metadata);
    expect(query.positiveSemantics, isEmpty);
    expect(query.timeRanges.single.annualStartMonth, 5);
    expect(query.timeRanges.single.annualStartDayOfMonth, 1);
    expect(query.timeRanges.single.annualEndMonth, 5);
    expect(query.timeRanges.single.annualEndDayOfMonth, 31);
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
            <String, int>{
              'start_month': 6,
              'start_day_of_month': 1,
              'end_month': 8,
              'end_day_of_month': 31,
            },
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
    expect(query.timeRanges.single.annualStartMonth, 6);
    expect(query.positiveSemanticTexts, contains('summer beach travel photo'));
    expect(query.positiveSemantics.every((item) => !item.containsCjk), isTrue);
  });

  test(
    'pure administrative place query clears accidental visual semantics',
    () {
      final query = SemanticQueryParserService().buildQueryFromStructuredJson(
        rawQuery: '青岛',
        jsonObject: <String, dynamic>{
          'version': 1,
          'raw_query': '青岛',
          'embedding_queries_en': <String>['a coastal city'],
          'objectbox_filters': <String, dynamic>{
            'absolute_date_ranges': const <Object>[],
            'annual_day_ranges': const <Object>[],
            'minute_of_day_ranges': const <Object>[],
            'weekdays': const <int>[],
            'geo': const <Map<String, dynamic>>[
              <String, dynamic>{
                'raw_name': '青岛',
                'normalized_names': <String>['青岛', '青岛市'],
                'kind_hint': 'city',
              },
            ],
          },
          'soft_filters': const <String, dynamic>{
            'visual_terms_en': <String>['an urban landmark'],
          },
          'negative_filters': const <String, dynamic>{
            'visual_terms_en': <String>[],
          },
        },
      );

      expect(query.queryType, SemanticSearchQueryType.metadata);
      expect(query.positiveSemantics, isEmpty);
      expect(query.recallSemantics, isEmpty);
      expect(query.coarseTags, isEmpty);
    },
  );

  test('specific POI query keeps stable visible semantics', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '五四广场',
      jsonObject: <String, dynamic>{
        'version': 1,
        'raw_query': '五四广场',
        'embedding_queries_en': <String>[
          'a city square',
          'a square near the sea with a large red landmark sculpture',
        ],
        'objectbox_filters': <String, dynamic>{
          'absolute_date_ranges': const <Object>[],
          'annual_day_ranges': const <Object>[],
          'minute_of_day_ranges': const <Object>[],
          'weekdays': const <int>[],
          'geo': const <Map<String, dynamic>>[
            <String, dynamic>{
              'raw_name': '五四广场',
              'normalized_names': <String>['五四广场'],
              'kind_hint': 'poi',
            },
          ],
        },
        'soft_filters': const <String, dynamic>{
          'visual_terms_en': <String>[
            'an open urban plaza near a coastal waterfront',
          ],
        },
        'negative_filters': const <String, dynamic>{
          'visual_terms_en': <String>[],
        },
      },
    );

    expect(query.queryType, SemanticSearchQueryType.concrete);
    expect(query.positiveSemanticTexts, contains('a city square'));
    expect(
      query.positiveSemanticTexts,
      contains('a square near the sea with a large red landmark sculpture'),
    );
  });

  test('client removes named places from visual semantics', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '青岛的海边',
      jsonObject: <String, dynamic>{
        'version': 1,
        'raw_query': '青岛的海边',
        'embedding_queries_en': <String>[
          'a Qingdao beach beside the sea',
          'ocean waves and coast',
        ],
        'objectbox_filters': <String, dynamic>{
          'absolute_date_ranges': const <Object>[],
          'annual_day_ranges': const <Object>[],
          'minute_of_day_ranges': const <Object>[],
          'weekdays': const <int>[],
          'geo': const <Map<String, dynamic>>[
            <String, dynamic>{
              'raw_name': '青岛',
              'normalized_names': <String>['青岛', '青岛市', 'Qingdao'],
              'kind_hint': 'city',
            },
          ],
        },
        'soft_filters': const <String, dynamic>{
          'visual_terms_en': <String>['coastal scenery near Qingdao'],
        },
        'negative_filters': const <String, dynamic>{
          'visual_terms_en': <String>[],
        },
      },
    );

    expect(
      <String>[
        ...query.positiveSemanticTexts,
        ...query.recallSemanticTexts,
      ].every((text) => !text.toLowerCase().contains('qingdao')),
      isTrue,
    );
    expect(query.positiveSemanticTexts, contains('a beach beside the sea'));
  });

  test('place plus visual subject keeps only visual search enabled', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '青岛的海边',
      jsonObject: <String, dynamic>{
        'version': 1,
        'raw_query': '青岛的海边',
        'embedding_queries_en': <String>['a beach beside the sea'],
        'objectbox_filters': <String, dynamic>{
          'absolute_date_ranges': const <Object>[],
          'annual_day_ranges': const <Object>[],
          'minute_of_day_ranges': const <Object>[],
          'weekdays': const <int>[],
          'geo': const <Map<String, dynamic>>[
            <String, dynamic>{
              'raw_name': '青岛',
              'normalized_names': <String>['青岛', '青岛市'],
              'kind_hint': 'city',
            },
          ],
        },
        'soft_filters': const <String, dynamic>{
          'visual_terms_en': <String>['ocean waves and coast'],
        },
        'negative_filters': const <String, dynamic>{
          'visual_terms_en': <String>[],
        },
      },
    );

    expect(query.queryType, SemanticSearchQueryType.concrete);
    expect(query.positiveSemanticTexts, <String>['a beach beside the sea']);
  });

  test('LLM-provided implicit time remains a mechanical filter', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '晚霞',
      jsonObject: <String, dynamic>{
        'query_type': 'concrete',
        'time_ranges': const <Object>[],
        'local_time_windows': const <Map<String, Object>>[
          <String, Object>{'start': '15:30', 'end': '21:00'},
        ],
        'locations': const <Object>[],
        'coarse_tags': const <Object>[],
        'tag_strictness': 'prefer',
        'positive_semantics': const <Map<String, Object>>[
          <String, Object>{'text': 'a late sunset sky', 'weight': 1.0},
        ],
        'recall_semantics': const <Map<String, Object>>[
          <String, Object>{'text': 'evening glow in the sky', 'weight': 1.0},
        ],
        'negative_semantics': const <Object>[],
        'attributes': const <String, Object>{},
        'estimated_result_count': const <String, Object>{
          'min': 1,
          'max': 40,
          'confidence': 0.8,
        },
      },
    );

    final localWindow = query.timeRanges.singleWhere(
      (range) => range.hasLocalTimeWindow,
    );
    expect(localWindow.localStartMinute, 15 * 60 + 30);
    expect(localWindow.localEndMinute, 21 * 60);
  });

  test('National Day holiday is represented as annual mechanical dates', () {
    final query = SemanticQueryParserService().buildQueryFromStructuredJson(
      rawQuery: '国庆节假期的旅行照片',
      jsonObject: <String, dynamic>{
        'query_type': 'collection',
        'time_ranges': const <Map<String, Object>>[
          <String, Object>{
            'annual_start_date': '10-01',
            'annual_end_date': '10-07',
            'reason': 'National Day holiday',
          },
        ],
        'local_time_windows': const <Object>[],
        'locations': const <Object>[],
        'coarse_tags': const <Map<String, Object>>[
          <String, Object>{
            'id': 'travel_landmark',
            'label_en': 'travel landmark',
            'confidence': 0.75,
          },
        ],
        'tag_strictness': 'prefer',
        'positive_semantics': const <Map<String, Object>>[
          <String, Object>{
            'text': 'a travel photo during a holiday trip',
            'weight': 1.0,
          },
        ],
        'recall_semantics': const <Map<String, Object>>[
          <String, Object>{
            'text': 'holiday travel sightseeing and vacation memories',
            'weight': 1.0,
          },
        ],
        'negative_semantics': const <Object>[],
        'attributes': const <String, Object>{},
        'estimated_result_count': const <String, Object>{
          'min': 1,
          'max': 160,
          'confidence': 0.72,
        },
      },
    );

    expect(query.timeRanges.single.annualStartMonth, 10);
    expect(query.timeRanges.single.annualStartDayOfMonth, 1);
    expect(query.timeRanges.single.annualEndMonth, 10);
    expect(query.timeRanges.single.annualEndDayOfMonth, 7);
    expect(query.timeRanges.single.hasDateBoundary, isFalse);
  });
}
