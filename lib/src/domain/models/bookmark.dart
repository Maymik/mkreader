class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.createdAt,
    this.chapterId,
    this.positionCfi,
    this.note,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final String? chapterId;
  final String? positionCfi;
  final String? note;
  final DateTime createdAt;
}
