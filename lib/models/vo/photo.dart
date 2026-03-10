class Photo {
  final String id;
  String? location;
  final String path;
  final DateTime dateTaken;
  final List<String> tags;
  final String? ocrSummary;
  final List<String> ocrTags;
  final bool isSelected;

  Photo({
    required this.id,
    this.location,
    required this.path,
    required this.dateTaken,
    this.tags = const [],
    this.ocrSummary,
    this.ocrTags = const [],
    this.isSelected = false,
  });

  Photo copyWith({
    String? id,
    String? path,
    DateTime? dateTaken,
    List<String>? tags,
    String? ocrSummary,
    List<String>? ocrTags,
    bool? isSelected,
  }) {
    return Photo(
      id: id ?? this.id,
      path: path ?? this.path,
      dateTaken: dateTaken ?? this.dateTaken,
      tags: tags ?? this.tags,
      ocrSummary: ocrSummary ?? this.ocrSummary,
      ocrTags: ocrTags ?? this.ocrTags,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
