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
}
