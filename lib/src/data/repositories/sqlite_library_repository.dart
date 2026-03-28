import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../core/persistence/app_database.dart';
import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/repositories/library_repository.dart';

class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> addBook(Book book) async {
    final db = await _database.instance;
    await db.insert(
      'books',
      {
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'description': book.description,
        'file_path': book.filePath,
        'cover_path': book.coverPath,
        'format': book.format,
        'imported_at': book.importedAt.toIso8601String(),
        'last_opened_at': book.lastOpenedAt?.toIso8601String(),
        'toc_json': jsonEncode(book.chapters.map((c) => c.toMap()).toList()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Book?> getBookById(String bookId) async {
    final db = await _database.instance;
    final rows = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapBook(rows.first);
  }

  @override
  Future<List<Book>> getBooks() async {
    final db = await _database.instance;
    final rows = await db.query('books', orderBy: 'imported_at DESC');
    return rows.map(_mapBook).toList();
  }

  Book _mapBook(Map<String, Object?> row) {
    final tocRaw = row['toc_json'] as String?;
    final decoded = tocRaw == null
        ? const <Map<String, dynamic>>[]
        : (jsonDecode(tocRaw) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

    return Book(
      id: row['id'] as String,
      title: row['title'] as String,
      author: row['author'] as String?,
      description: row['description'] as String?,
      filePath: row['file_path'] as String,
      coverPath: row['cover_path'] as String?,
      format: row['format'] as String,
      importedAt: DateTime.parse(row['imported_at'] as String),
      lastOpenedAt: row['last_opened_at'] == null
          ? null
          : DateTime.parse(row['last_opened_at'] as String),
      chapters: decoded.map(Chapter.fromMap).toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
  }
}
