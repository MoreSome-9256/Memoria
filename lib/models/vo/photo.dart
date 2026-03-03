class Photo {
  final String id;
  String? location;
  final String path;
  final DateTime dateTaken;
  final List<String> tags;
  final bool isSelected;

  Photo({
    required this.id,
    this.location,
    required this.path,
    required this.dateTaken,
    this.tags = const [],
    this.isSelected = false,
  });

  Photo copyWith({
    String? id,
    String? path,
    DateTime? dateTaken,
    List<String>? tags,
    bool? isSelected,
  }) {
    return Photo(
      id: id ?? this.id,
      path: path ?? this.path,
      dateTaken: dateTaken ?? this.dateTaken,
      tags: tags ?? this.tags,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
