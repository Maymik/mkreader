import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _dbName = 'mkreader.db';
  static const _dbVersion = 3;

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
            source_identifier TEXT,
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

        await db.execute('''
          CREATE TABLE bookmarks (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            chapter_id TEXT,
            chapter_index INTEGER NOT NULL,
            position_cfi TEXT,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_bookmarks_book_id ON bookmarks(book_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE books ADD COLUMN source_identifier TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS bookmarks (
              id TEXT PRIMARY KEY,
              book_id TEXT NOT NULL,
              chapter_id TEXT,
              chapter_index INTEGER NOT NULL,
              position_cfi TEXT,
              note TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bookmarks_book_id ON bookmarks(book_id)',
          );
        }
      },
    );
    return _database!;
  }
}
