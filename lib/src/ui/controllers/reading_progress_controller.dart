import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reading_progress.dart';
import '../providers/app_providers.dart';

final readingProgressProvider =
    FutureProvider.family<ReadingProgress?, String>((ref, bookId) {
  return ref.read(readingProgressRepositoryProvider).getProgressForBook(bookId);
});

final readingProgressControllerProvider =
    Provider<ReadingProgressController>((ref) {
  return ReadingProgressController(ref);
});

class ReadingProgressController {
  const ReadingProgressController(this._ref);

  final Ref _ref;

  Future<void> saveProgress(ReadingProgress progress) async {
    await _ref.read(readingProgressRepositoryProvider).saveProgress(progress);
    _ref.invalidate(readingProgressProvider(progress.bookId));
  }
}
