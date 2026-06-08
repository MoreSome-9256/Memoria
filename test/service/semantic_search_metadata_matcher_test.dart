import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/vo/semantic_search_models.dart';
import 'package:photo_album/service/semantic_search_metadata_matcher.dart';

PhotoEntity _photo({
  required int id,
  required int timestamp,
  String? province,
  String? city,
  String? district,
  String? locationName,
  String? formattedAddress,
  List<String>? aiTags,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = timestamp
    ..width = 1000
    ..height = 1000
    ..province = province
    ..city = city
    ..district = district
    ..locationName = locationName
    ..formattedAddress = formattedAddress
    ..aiTags = aiTags;
}

SemanticSearchQuery _query({
  List<SemanticSearchTimeRange> ranges = const <SemanticSearchTimeRange>[],
  List<SemanticSearchLocation> locations = const <SemanticSearchLocation>[],
}) {
  return SemanticSearchQuery.empty(
    'test',
  ).copyWith(timeRanges: ranges, locations: locations);
}

void main() {
  const matcher = SemanticSearchMetadataMatcher();

  group('SemanticSearchMetadataMatcher time', () {
    test('normalizes legacy second timestamps before date comparison', () {
      final day = DateTime(2026, 6, 8, 12);
      final photo = _photo(
        id: 1,
        timestamp: day.millisecondsSinceEpoch ~/ 1000,
      );
      final query = _query(
        ranges: <SemanticSearchTimeRange>[
          SemanticSearchTimeRange(
            startTimeMs: DateTime(2026, 6, 8).millisecondsSinceEpoch,
            endTimeMs: DateTime(
              2026,
              6,
              9,
            ).subtract(const Duration(milliseconds: 1)).millisecondsSinceEpoch,
            reason: 'day',
          ),
        ],
      );

      expect(matcher.matchesTime(photo, query), isTrue);
    });

    test('matches cross-midnight local windows with explicit offset', () {
      final photo = _photo(
        id: 2,
        timestamp: DateTime.utc(2026, 6, 8, 18).millisecondsSinceEpoch,
      );
      final query = _query(
        ranges: const <SemanticSearchTimeRange>[
          SemanticSearchTimeRange(
            startTimeMs: null,
            endTimeMs: null,
            reason: 'night',
            utcOffsetMinutes: 8 * 60,
            localStartMinute: 22 * 60,
            localEndMinute: 5 * 60,
          ),
        ],
      );

      expect(matcher.matchesTime(photo, query), isTrue);
    });

    test('keeps local time windows active even when utc offset is absent', () {
      final photo = _photo(
        id: 3,
        timestamp: DateTime(2026, 6, 8, 23, 30).millisecondsSinceEpoch,
      );
      final range = const SemanticSearchTimeRange(
        startTimeMs: null,
        endTimeMs: null,
        reason: 'late night',
        localStartMinute: 22 * 60,
        localEndMinute: 23 * 60 + 59,
      );

      expect(range.hasLocalTimeWindow, isTrue);
      expect(
        matcher.matchesTime(
          photo,
          _query(ranges: <SemanticSearchTimeRange>[range]),
        ),
        isTrue,
      );
    });
  });

  group('SemanticSearchMetadataMatcher location', () {
    test('matches POI aliases against stored Chinese scenic names', () {
      final photo = _photo(
        id: 4,
        timestamp: 1,
        city: '南京市',
        district: '秦淮区',
        locationName: '夫子庙秦淮风光带',
        formattedAddress: '江苏省南京市秦淮区夫子庙景区',
      );

      final match = matcher.matchLocation(photo, const <SemanticSearchLocation>[
        SemanticSearchLocation(
          text: 'Nanjing Confucius Temple',
          type: 'poi',
          aliases: <String>['南京夫子庙', '夫子庙', 'Fuzimiao'],
        ),
      ]);

      expect(match.isStrictMatch, isTrue);
      expect(match.matchedLocations, contains('Nanjing Confucius Temple'));
    });

    test('keeps city matches broader than POI matches', () {
      final photo = _photo(id: 5, timestamp: 1, city: '青岛市');

      expect(
        matcher.matchesLocation(photo, const <SemanticSearchLocation>[
          SemanticSearchLocation(text: 'Qingdao', type: 'city'),
        ]),
        isFalse,
      );
      expect(
        matcher.matchesLocation(photo, const <SemanticSearchLocation>[
          SemanticSearchLocation(
            text: 'Qingdao',
            type: 'city',
            aliases: <String>['青岛'],
          ),
        ]),
        isTrue,
      );
    });
  });

  test('maps sanitized visual tags to coarse tag matches', () {
    final photo = _photo(
      id: 6,
      timestamp: 1,
      aiTags: const <String>['美食', '天空'],
    );

    final result = matcher
        .matchCoarseTags(photo, const <SemanticSearchCoarseTag>[
          SemanticSearchCoarseTag(
            id: 'food_drink',
            labelZh: '美食饮品',
            labelEn: 'food and drink',
            confidence: 0.9,
          ),
        ]);

    expect(result.matchedLabels, contains('美食饮品'));
    expect(result.confidence, 0.9);
  });
}
