import 'photo.dart';

class StorySection {
  final String text;
  final Photo photo;

  StorySection({required this.text, required this.photo});

  StorySection copyWith({
    String? text,
    Photo? photo,
  }) {
    return StorySection(
      text: text ?? this.text,
      photo: photo ?? this.photo,
    );
  }
}
