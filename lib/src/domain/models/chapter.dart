class Chapter {
  const Chapter({
    required this.id,
    required this.bookId,
    required this.title,
    required this.index,
    required this.href,
  });

  final String id;
  final String bookId;
  final String title;
  final int index;
  final String href;

  Chapter copyWith({
    String? id,
    String? bookId,
    String? title,
    int? index,
    String? href,
  }) {
    return Chapter(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      title: title ?? this.title,
      index: index ?? this.index,
      href: href ?? this.href,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookId': bookId,
      'title': title,
      'index': index,
      'href': href,
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'] as String,
      bookId: map['bookId'] as String,
      title: map['title'] as String,
      index: map['index'] as int,
      href: map['href'] as String,
    );
  }
}
