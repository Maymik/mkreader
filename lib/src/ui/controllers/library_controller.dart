import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import 'reading_progress_controller.dart';
import '../providers/app_providers.dart';

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<Book>>(LibraryController.new);

final bookByIdProvider = FutureProvider.family<Book?, String>((ref, bookId) {
  return ref.read(libraryRepositoryProvider).getBookById(bookId);
});

class LibraryController extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    return ref.read(libraryRepositoryProvider).getBooks();
  }

  Future<String?> importEpub() async {
    try {
      final importedBook =
          await ref.read(epubImportServiceProvider).importFromDeviceStorage();
      if (importedBook == null) {
        return null;
      }

      await ref.read(libraryRepositoryProvider).addBook(importedBook);
      state = AsyncData(await ref.read(libraryRepositoryProvider).getBooks());
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<String?> deleteBook(String bookId) async {
    final previousBooks = state.valueOrNull ?? const <Book>[];
    state = AsyncData(
      previousBooks.where((book) => book.id != bookId).toList(),
    );

    try {
      await ref.read(libraryRepositoryProvider).deleteBook(bookId);
      await ref.read(readingProgressRepositoryProvider).deleteProgressForBook(
            bookId,
          );
      ref.invalidate(bookByIdProvider(bookId));
      ref.invalidate(readingProgressProvider(bookId));
      return null;
    } catch (error) {
      state = AsyncData(previousBooks);
      return 'Failed to delete book: $error';
    }
  }
}
