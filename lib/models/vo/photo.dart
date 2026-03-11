class Photo {
  final String id;
  String? location;
  final String path;
  final DateTime dateTaken;
  final List<String> tags;
  final String? caption;
  final String? ocrSummary;
  final List<String> ocrTags;
  final bool isSelected;

  Photo({
    required this.id,
    this.location,
    required this.path,
    required this.dateTaken,
    this.tags = const [],
    this.caption,
    this.ocrSummary,
    this.ocrTags = const [],
    this.isSelected = false,
  });

  Photo copyWith({
    String? id,
    String? location,
    String? path,
    DateTime? dateTaken,
    List<String>? tags,
    String? caption,
    String? ocrSummary,
    List<String>? ocrTags,
    bool? isSelected,
  }) {
    return Photo(
      id: id ?? this.id,
      location: location ?? this.location,
      path: path ?? this.path,
      dateTaken: dateTaken ?? this.dateTaken,
      tags: tags ?? this.tags,
      caption: caption ?? this.caption,
      ocrSummary: ocrSummary ?? this.ocrSummary,
      ocrTags: ocrTags ?? this.ocrTags,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
