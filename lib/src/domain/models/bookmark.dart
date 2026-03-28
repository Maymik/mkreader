class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.createdAt,
    this.chapterId,
    this.cfi,
    this.note,
  });

  final String id;
  final String bookId;
  final String? chapterId;
  final String? cfi;
  final String? note;
  final DateTime createdAt;
}
