import '../models/vo/photo.dart';
import '../models/ai_theme.dart';
import '../models/event.dart';
import '../models/story.dart';

class MockData {
  // Mock Photos
  static List<Photo> getMockPhotos(int count, DateTime baseDate) {
    return List.generate(
      count,
      (index) => Photo(
        id: 'photo_$index',
        path: 'https://picsum.photos/seed/$index/800/600',
        dateTaken: baseDate.add(Duration(hours: index * 2)),
        tags: ['旅行', '海滩', '夏天'][index % 3] == '旅行' ? ['旅行'] : ['海滩'],
      ),
    );
  }

  // Mock AI Themes
  static List<AITheme> getMockThemes() {
    return [
      AITheme(id: 'theme_1', emoji: '🌊', title: '夏日旅行', subtitle: '海风与阳光'),
      AITheme(id: 'theme_2', emoji: '😄', title: '快乐时光', subtitle: '我们的假期'),
      AITheme(id: 'theme_3', emoji: '🏖️', title: '海滩记忆', subtitle: '沙滩与浪花'),
      AITheme(id: 'theme_4', emoji: '📸', title: '美好瞬间', subtitle: '定格的回忆'),
    ];
  }

  // Mock Events
  static List<Event> getMockEvents() {
    return [
      Event(
        id: 'event_1',
        title: '青岛海边之旅',
        season: '夏天',
        year: 2024,
        location: '青岛',
        startDate: DateTime(2024, 8, 15),
        endDate: DateTime(2024, 8, 18),
        photos: getMockPhotos(12, DateTime(2024, 8, 15, 10, 0)),
        tags: ['旅行', '海滩', '夏天'],
        aiThemes: getMockThemes(),
      ),
      Event(
        id: 'event_2',
        title: '春日赏花',
        season: '春天',
        year: 2024,
        location: '北京',
        startDate: DateTime(2024, 4, 10),
        endDate: DateTime(2024, 4, 12),
        photos: getMockPhotos(8, DateTime(2024, 4, 10, 14, 0)),
        tags: ['春天', '赏花', '出游'],
        aiThemes: [
          AITheme(
            id: 'theme_spring_1',
            emoji: '🌸',
            title: '春日物语',
            subtitle: '樱花盛开的季节',
          ),
          AITheme(
            id: 'theme_spring_2',
            emoji: '🌿',
            title: '绿意盎然',
            subtitle: '春天的气息',
          ),
        ],
      ),
      Event(
        id: 'event_3',
        title: '秋日登山',
        season: '秋天',
        year: 2024,
        location: '香山',
        startDate: DateTime(2024, 10, 5),
        endDate: DateTime(2024, 10, 5),
        photos: getMockPhotos(15, DateTime(2024, 10, 5, 8, 0)),
        tags: ['登山', '秋天', '红叶'],
        aiThemes: [
          AITheme(
            id: 'theme_autumn_1',
            emoji: '🍂',
            title: '秋日登高',
            subtitle: '层林尽染',
          ),
          AITheme(
            id: 'theme_autumn_2',
            emoji: '⛰️',
            title: '山间漫步',
            subtitle: '秋高气爽',
          ),
        ],
      ),
      Event(
        id: 'event_4',
        title: '冬日滑雪',
        season: '冬天',
        year: 2024,
        location: '崇礼',
        startDate: DateTime(2024, 12, 20),
        endDate: DateTime(2024, 12, 22),
        photos: getMockPhotos(10, DateTime(2024, 12, 20, 9, 0)),
        tags: ['滑雪', '冬天', '运动'],
        aiThemes: [
          AITheme(
            id: 'theme_winter_1',
            emoji: '⛷️',
            title: '冰雪奇缘',
            subtitle: '雪山飞驰',
          ),
          AITheme(
            id: 'theme_winter_2',
            emoji: '❄️',
            title: '冬日激情',
            subtitle: '白色世界',
          ),
        ],
      ),
    ];
  }

  // Mock Stories
  static List<Story> getMockStories() {
    final events = getMockEvents();
    return [
      Story(
        id: 'story_1',
        title: '海风与阳光：青岛之旅',
        subtitle: '那个夏天，我们与海相遇',
        heroImage: events[0].photos[0],
        blocks: [
          StoryBlock(
            text:
                '八月的青岛，海风带着咸湿的味道扑面而来。金色的阳光洒在波光粼粼的海面上，远处的帆影若隐若现。'
                '我们沿着海岸线漫步，脚下是细软的沙滩，耳边是海浪的呢喃。这是一场期待已久的旅行，也是一段难忘的回忆。',
            photo: events[0].photos[1],
          ),
          StoryBlock(
            text:
                '在栈桥上，我们迎着海风拍下了最美的合照。那一刻，时间仿佛静止，只有海鸥的鸣叫和浪花拍岸的声音。'
                '夕阳西下时，整个天空被染成了橙红色，海面泛着金光，美得让人不想离去。',
            photo: events[0].photos[2],
          ),
          StoryBlock(
            text: '青岛的记忆，就像这片海一样，深邃而温柔。离开的那天，我们约定，下个夏天，还要再来。',
            photo: events[0].photos[3],
          ),
        ],
        createdAt: DateTime(2024, 8, 20),
        eventId: 'event_1',
      ),
      Story(
        id: 'story_2',
        title: '春日物语：樱花盛开时',
        subtitle: '春天的浪漫与诗意',
        heroImage: events[1].photos[0],
        blocks: [
          StoryBlock(
            text:
                '四月的北京，春意盎然。樱花如期而至，将整个公园装点成粉色的梦境。'
                '微风拂过，花瓣纷纷扬扬地飘落，像是下了一场粉色的雨。',
            photo: events[1].photos[1],
          ),
          StoryBlock(
            text: '我们在樱花树下拍照留念，笑声和快门声交织在一起。春天的气息让人心情愉悦，一切都显得那么美好。',
            photo: events[1].photos[2],
          ),
          StoryBlock(
            text: '春天总是短暂的，但这份美好会永远留在心中。樱花会再开，我们也会再相聚。',
            photo: events[1].photos[3],
          ),
        ],
        createdAt: DateTime(2024, 4, 15),
        eventId: 'event_2',
      ),
    ];
  }

  // Get events grouped by year and season
  static Map<String, List<Event>> getGroupedEvents() {
    final events = getMockEvents();
    final grouped = <String, List<Event>>{};

    for (var event in events) {
      final key = '${event.year} · ${event.season}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(event);
    }

    return grouped;
  }
}
