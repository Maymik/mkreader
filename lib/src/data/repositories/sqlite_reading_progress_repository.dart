import 'package:sqflite/sqflite.dart';

import '../../core/persistence/app_database.dart';
import '../../domain/models/reading_progress.dart';
import '../../domain/repositories/reading_progress_repository.dart';

class SqliteReadingProgressRepository implements ReadingProgressRepository {
  SqliteReadingProgressRepository(this._database);

  final AppDatabase _database;

  @override
  Future<ReadingProgress?> getProgressForBook(String bookId) async {
    final db = await _database.instance;
    final rows = await db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final rawProgression = row['progression'];
    return ReadingProgress(
      bookId: row['book_id'] as String,
      chapterId: row['chapter_id'] as String?,
      chapterIndex: row['chapter_index'] as int,
      progression: (rawProgression as num).toDouble(),
      cfi: row['cfi'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    final db = await _database.instance;
    await db.insert(
      'reading_progress',
      {
        'book_id': progress.bookId,
        'chapter_id': progress.chapterId,
        'chapter_index': progress.chapterIndex,
        'progression': progress.progression,
        'cfi': progress.cfi,
        'updated_at': progress.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
