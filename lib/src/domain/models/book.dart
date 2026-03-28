import 'chapter.dart';

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.importedAt,
    this.author,
    this.description,
    this.coverPath,
    this.lastOpenedAt,
    this.chapters = const [],
    this.format = 'epub',
  });

  final String id;
  final String title;
  final String? author;
  final String? description;
  final String filePath;
  final String? coverPath;
  final String format;
  final DateTime importedAt;
  final DateTime? lastOpenedAt;
  final List<Chapter> chapters;

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? description,
    String? filePath,
    String? coverPath,
    String? format,
    DateTime? importedAt,
    DateTime? lastOpenedAt,
    List<Chapter>? chapters,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      format: format ?? this.format,
      importedAt: importedAt ?? this.importedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      chapters: chapters ?? this.chapters,
    );
  }
}
