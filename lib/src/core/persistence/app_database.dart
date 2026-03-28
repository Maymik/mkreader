import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _dbName = 'mkreader.db';
  static const _dbVersion = 1;

  Database? _database;

  Future<Database> get instance async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT,
            description TEXT,
            file_path TEXT NOT NULL,
            cover_path TEXT,
            format TEXT NOT NULL,
            imported_at TEXT NOT NULL,
            last_opened_at TEXT,
            toc_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE reading_progress (
            book_id TEXT PRIMARY KEY,
            chapter_id TEXT,
            chapter_index INTEGER NOT NULL,
            progression REAL NOT NULL,
            cfi TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }
}
