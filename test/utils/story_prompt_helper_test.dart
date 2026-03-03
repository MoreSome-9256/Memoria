import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/story_prompt_helper.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  String? formattedAddress,
  String? district,
  String? city,
  String? province,
  double? lat,
  double? lon,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/p$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 1200
    ..height = 900
    ..formattedAddress = formattedAddress
    ..district = district
    ..city = city
    ..province = province
    ..latitude = lat
    ..longitude = lon
    ..aiTags = ['海边', '日落'];
}

EventEntity _event() {
  final start = DateTime(2026, 5, 16, 8, 30).millisecondsSinceEpoch;
  final end = DateTime(2026, 5, 17, 20, 5).millisecondsSinceEpoch;
  return EventEntity()
    ..id = 1
    ..title = '深圳两日'
    ..startTime = start
    ..endTime = end
    ..city = '深圳市'
    ..province = '广东省'
    ..avgLatitude = 22.55
    ..avgLongitude = 114.06;
}

void main() {
  group('StoryPromptHelper', () {
    test(
      'photo description prefers formatted address and keeps coordinates',
      () {
        final photos = [
          _photo(
            id: 1,
            time: DateTime(2026, 5, 16, 8, 30),
            formattedAddress: '广东省深圳市南山区深圳湾公园',
            district: '南山区',
            city: '深圳市',
            province: '广东省',
            lat: 22.5139,
            lon: 113.9442,
          ),
        ];

        final desc = StoryPromptHelper.buildPhotoDescriptions(photos).single;

        expect(desc, contains('地址：广东省深圳市南山区深圳湾公园'));
        expect(desc, contains('行政区：广东省深圳市南山区'));
        expect(desc, contains('坐标：22.513900,113.944200'));
      },
    );

    test(
      'photo description can fall back to coordinates when address missing',
      () {
        final photos = [
          _photo(
            id: 2,
            time: DateTime(2026, 5, 16, 12, 40),
            lat: 22.5393,
            lon: 113.9736,
          ),
        ];

        final desc = StoryPromptHelper.buildPhotoDescriptions(photos).single;

        expect(desc, contains('坐标：22.539300,113.973600'));
        expect(desc, isNot(contains('地址：')));
      },
    );

    test('story prompt includes location mode and anti-fabrication rules', () {
      final prompt = StoryPromptHelper.buildStoryPrompt(
        title: '深圳两天旅行',
        subtitle: '海风与城市夜景',
        event: _event(),
        photoDescriptions: ['Image 0: test'],
        isShort: false,
        locationMode: 'time-tag-only',
      );

      expect(prompt, contains('位置线索模式：time-tag-only'));
      expect(prompt, contains('严禁编造未提供的地名'));
      expect(prompt, contains('仅根据时间与标签叙事'));
      expect(prompt, contains('事件中心坐标：22.550000,114.060000'));
    });
  });
}
