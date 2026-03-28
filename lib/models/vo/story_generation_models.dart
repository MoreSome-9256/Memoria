import '../ai_theme.dart';
import '../entity/photo_entity.dart';
import '../entity/story_entity.dart';
import '../event.dart';
import 'photo.dart';

enum StoryGenerationMode {
  deepseekTags,
  localCaptionThenDeepseek,
  localDirectVlm,
}

extension StoryGenerationModeX on StoryGenerationMode {
  String get title {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return 'DeepSeek 标签故事';
      case StoryGenerationMode.localCaptionThenDeepseek:
        return '本地 VLM Caption + DeepSeek';
      case StoryGenerationMode.localDirectVlm:
        return '本地 VLM 直接读图';
    }
  }

  String get subtitle {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return '直接根据标签、OCR、时间和地点生成，速度最快';
      case StoryGenerationMode.localCaptionThenDeepseek:
        return '先逐图补 caption，再交给 DeepSeek 串成故事';
      case StoryGenerationMode.localDirectVlm:
        return '直接由本地 VLM 读图并写故事，不依赖云端';
    }
  }

  bool get requiresLocalVlm {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return false;
      case StoryGenerationMode.localCaptionThenDeepseek:
      case StoryGenerationMode.localDirectVlm:
        return true;
    }
  }
}

enum StoryGenerationProgressStatus {
  pending,
  inProgress,
  completed,
  failed,
}

class StoryGenerationProgressStep {
  const StoryGenerationProgressStep({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
    this.bullets = const <String>[],
    this.previewImagePaths = const <String>[],
  });

  final String id;
  final String title;
  final StoryGenerationProgressStatus status;
  final String? detail;
  final List<String> bullets;
  final List<String> previewImagePaths;

  StoryGenerationProgressStep copyWith({
    StoryGenerationProgressStatus? status,
    String? detail,
    List<String>? bullets,
    List<String>? previewImagePaths,
  }) {
    return StoryGenerationProgressStep(
      id: id,
      title: title,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      bullets: bullets ?? this.bullets,
      previewImagePaths: previewImagePaths ?? this.previewImagePaths,
    );
  }
}

class StoryGenerationProgressState {
  const StoryGenerationProgressState({
    required this.steps,
    this.headline,
    this.errorMessage,
    this.isCompleted = false,
  });

  final List<StoryGenerationProgressStep> steps;
  final String? headline;
  final String? errorMessage;
  final bool isCompleted;
}

class StoryGenerationRequest {
  const StoryGenerationRequest({
    required this.event,
    required this.selectedPhotos,
    required this.selectedTheme,
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.isHorizontal,
    required this.targetPlatform,
    this.semanticSearchQuery,
  });

  final Event event;
  final List<Photo> selectedPhotos;
  final AITheme selectedTheme;
  final String title;
  final String subtitle;
  final StoryGenerationMode mode;
  final bool isHorizontal;
  final String targetPlatform;
  final String? semanticSearchQuery;
}

class StoryGenerationOutput {
  const StoryGenerationOutput({
    required this.story,
    required this.photos,
  });

  final StoryEntity story;
  final List<PhotoEntity> photos;
}
