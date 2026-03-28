import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
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

  Future<void> importEpub() async {
    final importedBook =
        await ref.read(epubImportServiceProvider).importFromDeviceStorage();
    if (importedBook == null) {
      return;
    }

    await ref.read(libraryRepositoryProvider).addBook(importedBook);
    state = AsyncData(await ref.read(libraryRepositoryProvider).getBooks());
  }
}
