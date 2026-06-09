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

    test('matches recurring summer months across different years', () {
      const range = SemanticSearchTimeRange(
        startTimeMs: null,
        endTimeMs: null,
        reason: 'summer in any year',
        recurringStartMonth: 6,
        recurringEndMonth: 10,
      );
      final summer2022 = _photo(
        id: 10,
        timestamp: DateTime(2022, 7, 1).millisecondsSinceEpoch,
      );
      final summer2025 = _photo(
        id: 11,
        timestamp: DateTime(2025, 10, 1).millisecondsSinceEpoch,
      );
      final winter = _photo(
        id: 12,
        timestamp: DateTime(2025, 12, 1).millisecondsSinceEpoch,
      );

      expect(
        matcher.matchesTime(summer2022, _query(ranges: const [range])),
        isTrue,
      );
      expect(
        matcher.matchesTime(summer2025, _query(ranges: const [range])),
        isTrue,
      );
      expect(
        matcher.matchesTime(winter, _query(ranges: const [range])),
        isFalse,
      );
    });

    test('matches recurring winter range across year boundary', () {
      const range = SemanticSearchTimeRange(
        startTimeMs: null,
        endTimeMs: null,
        reason: 'winter in any year',
        recurringStartMonth: 12,
        recurringEndMonth: 2,
      );

      expect(
        matcher.matchesTime(
          _photo(
            id: 13,
            timestamp: DateTime(2024, 12, 1).millisecondsSinceEpoch,
          ),
          _query(ranges: const [range]),
        ),
        isTrue,
      );
      expect(
        matcher.matchesTime(
          _photo(
            id: 14,
            timestamp: DateTime(2025, 2, 1).millisecondsSinceEpoch,
          ),
          _query(ranges: const [range]),
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

    test('does not treat broad POI context as an exact POI hit', () {
      final query = const <SemanticSearchLocation>[
        SemanticSearchLocation(
          text: '情侣园',
          type: 'poi',
          aliases: <String>['南京情侣园', '玄武湖景区', '锁金村'],
        ),
      ];
      final exactPoi = _photo(
        id: 7,
        timestamp: 1,
        city: '南京市',
        locationName: '情侣园',
        formattedAddress: '江苏省南京市玄武区情侣园',
      );
      final scenicContext = _photo(
        id: 8,
        timestamp: 1,
        city: '南京市',
        locationName: '玄武湖景区',
        formattedAddress: '江苏省南京市玄武区玄武湖景区',
      );
      final villageContext = _photo(
        id: 9,
        timestamp: 1,
        city: '南京市',
        locationName: '锁金村',
        formattedAddress: '江苏省南京市玄武区锁金村',
      );

      expect(matcher.matchesLocation(exactPoi, query), isTrue);
      expect(matcher.matchesLocation(scenicContext, query), isFalse);
      expect(matcher.matchesLocation(villageContext, query), isFalse);
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
