class Photo {
  final String id;
  String? location;
  final String path;
  final DateTime dateTaken;
  final List<String> tags;
  final String? caption;
  final String? vlmCaption;
  final String? ocrSummary;
  final List<String> ocrTags;
  final bool isSelected;
  final int width;
  final int height;
  final List<dynamic>? faces; // 存放人脸数据 (可以兼容传入 FaceEntity)

  Photo({
    required this.id,
    this.location,
    required this.path,
    required this.dateTaken,
    this.tags = const [],
    this.caption,
    this.vlmCaption = '',
    this.ocrSummary,
    this.ocrTags = const [],
    this.isSelected = false,
    // 默认给 0 和 null，这样你项目里其他创建 Photo 的旧代码就不会报错
    this.width = 0,
    this.height = 0,
    this.faces,
  });

  Photo copyWith({
    String? id,
    String? location,
    String? path,
    DateTime? dateTaken,
    List<String>? tags,
    String? caption,
    String? vlmCaption,
    String? ocrSummary,
    List<String>? ocrTags,
    bool? isSelected,
    int? width,
    int? height,
    List<dynamic>? faces,
  }) {
    return Photo(
      id: id ?? this.id,
      location: location ?? this.location,
      path: path ?? this.path,
      dateTaken: dateTaken ?? this.dateTaken,
      tags: tags ?? this.tags,
      caption: caption ?? this.caption,
      vlmCaption: vlmCaption ?? this.vlmCaption,
      ocrSummary: ocrSummary ?? this.ocrSummary,
      ocrTags: ocrTags ?? this.ocrTags,
      isSelected: isSelected ?? this.isSelected,
      width: width ?? this.width,
      height: height ?? this.height,
      faces: faces ?? this.faces,
    );
  }
}
