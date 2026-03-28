import '../models/reading_progress.dart';

abstract class ReadingProgressRepository {
  Future<ReadingProgress?> getProgressForBook(String bookId);
  Future<void> saveProgress(ReadingProgress progress);
}
