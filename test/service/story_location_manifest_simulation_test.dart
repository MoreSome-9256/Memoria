import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/story_prompt_helper.dart';

List<Map<String, dynamic>> _loadShenzhenManifestPhotos() {
  final file = File('imgs/shenzhen_2day_trip/manifest.json');
  if (file.existsSync()) {
    final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return (manifest['photos'] as List).cast<Map<String, dynamic>>();
  }

  return <Map<String, dynamic>>[
    <String, dynamic>{
      'assetId': 'sz_1',
      'path': 'imgs/shenzhen_2day_trip/1.jpg',
      'addressCn': '广东省深圳市南山区深圳湾公园观海栈道',
      'extInfo': <String, dynamic>{
        'timestampMs': DateTime(2026, 5, 16, 8, 30).millisecondsSinceEpoch,
        'width': 4032,
        'height': 3024,
        'latitude': 22.5139,
        'longitude': 113.9442,
      },
    },
    <String, dynamic>{
      'assetId': 'sz_2',
      'path': 'imgs/shenzhen_2day_trip/2.jpg',
      'addressCn': '广东省深圳市南山区世界之窗景区',
      'extInfo': <String, dynamic>{
        'timestampMs': DateTime(2026, 5, 16, 14, 10).millisecondsSinceEpoch,
        'width': 4032,
        'height': 3024,
        'latitude': 22.5401,
        'longitude': 113.9736,
      },
    },
    <String, dynamic>{
      'assetId': 'sz_3',
      'path': 'imgs/shenzhen_2day_trip/3.jpg',
      'addressCn': '广东省深圳市盐田区大梅沙海滨公园',
      'extInfo': <String, dynamic>{
        'timestampMs': DateTime(2026, 5, 17, 17, 45).millisecondsSinceEpoch,
        'width': 4032,
        'height': 3024,
        'latitude': 22.6034,
        'longitude': 114.3105,
      },
    },
  ];
}

void main() {
  test(
    'shenzhen manifest simulation carries scenic-level location hints into prompt',
    () {
      final photosRaw = _loadShenzhenManifestPhotos();

      final photos = <PhotoEntity>[];
      for (var i = 0; i < photosRaw.length; i++) {
        final item = photosRaw[i];
        final ext = (item['extInfo'] as Map<String, dynamic>);
        photos.add(
          PhotoEntity()
            ..id = i + 1
            ..assetId = item['assetId'] as String
            ..path = item['path'] as String
            ..timestamp = ext['timestampMs'] as int
            ..width = ext['width'] as int
            ..height = ext['height'] as int
            ..latitude = (ext['latitude'] as num).toDouble()
            ..longitude = (ext['longitude'] as num).toDouble()
            ..formattedAddress = item['addressCn'] as String
            ..city = '深圳市'
            ..province = '广东省'
            ..aiTags = ['旅行', '城市'],
        );
      }

      final event = EventEntity()
        ..id = 1
        ..title = '深圳两天'
        ..startTime = photos.first.timestamp
        ..endTime = photos.last.timestamp
        ..city = '深圳市'
        ..province = '广东省'
        ..avgLatitude = 22.55
        ..avgLongitude = 114.06;

      final descriptions = StoryPromptHelper.buildPhotoDescriptions(photos);
      final prompt = StoryPromptHelper.buildStoryPrompt(
        title: '深圳两天旅行',
        subtitle: '城市海风与夜景',
        event: event,
        photoDescriptions: descriptions,
        isShort: false,
        locationMode: 'address',
      );

      expect(prompt, contains('深圳湾公园'));
      expect(prompt, contains('世界之窗'));
      expect(prompt, contains('大梅沙海滨公园'));
      expect(prompt, contains('严禁编造未提供的地名'));
    },
  );
}
