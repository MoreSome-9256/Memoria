import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/story_prompt_helper.dart';

void main() {
  test(
    'shenzhen manifest simulation carries scenic-level location hints into prompt',
    () {
      final file = File('imgs/shenzhen_2day_trip/manifest.json');
      expect(file.existsSync(), isTrue);

      final manifest =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final photosRaw = (manifest['photos'] as List)
          .cast<Map<String, dynamic>>();

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
