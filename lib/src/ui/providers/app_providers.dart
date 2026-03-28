import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persistence/app_database.dart';
import '../../data/repositories/shared_prefs_reader_settings_repository.dart';
import '../../data/repositories/sqlite_library_repository.dart';
import '../../data/repositories/sqlite_reading_progress_repository.dart';
import '../../data/services/epub_content_service.dart';
import '../../data/services/file_picker_epub_import_service.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/reader_settings_repository.dart';
import '../../domain/repositories/reading_progress_repository.dart';
import '../../domain/services/epub_import_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return SqliteLibraryRepository(ref.read(appDatabaseProvider));
});

final readingProgressRepositoryProvider =
    Provider<ReadingProgressRepository>((ref) {
  return SqliteReadingProgressRepository(ref.read(appDatabaseProvider));
});

final readerSettingsRepositoryProvider =
    Provider<ReaderSettingsRepository>((ref) {
  return SharedPrefsReaderSettingsRepository();
});

final epubImportServiceProvider = Provider<EpubImportService>((ref) {
  return FilePickerEpubImportService();
});

final epubContentServiceProvider = Provider<EpubContentService>((ref) {
  return EpubContentService();
});
