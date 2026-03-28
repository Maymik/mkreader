import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../controllers/library_controller.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            ref.read(libraryControllerProvider.notifier).importEpub(),
        icon: const Icon(Icons.file_open),
        label: const Text('Import EPUB'),
      ),
      body: libraryState.when(
        data: (books) {
          if (books.isEmpty) {
            return const Center(
              child: Text('No books yet. Tap "Import EPUB" to start.'),
            );
          }

          return ListView.separated(
            itemCount: books.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final book = books[index];
              return ListTile(
                title: Text(book.title),
                subtitle: Text(book.author ?? 'Unknown author'),
                trailing: IconButton(
                  icon: const Icon(Icons.menu_book),
                  onPressed: () => context.push(AppRoutes.readerPath(book.id)),
                  tooltip: 'Read',
                ),
                onTap: () => context.push(AppRoutes.bookDetailsPath(book.id)),
              );
            },
          );
        },
        error: (error, _) =>
            Center(child: Text('Failed to load library: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
