class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.updatedAt,
    this.chapterId,
    this.chapterIndex = 0,
    this.progression = 0,
    this.cfi,
  });

  final String bookId;
  final String? chapterId;
  final int chapterIndex;
  final double progression;
  final String? cfi;
  final DateTime updatedAt;

  ReadingProgress copyWith({
    String? bookId,
    String? chapterId,
    int? chapterIndex,
    double? progression,
    String? cfi,
    DateTime? updatedAt,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapterId: chapterId ?? this.chapterId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      progression: progression ?? this.progression,
      cfi: cfi ?? this.cfi,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
