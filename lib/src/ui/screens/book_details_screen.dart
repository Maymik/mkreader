import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../controllers/library_controller.dart';

class BookDetailsScreen extends ConsumerWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookByIdProvider(bookId));

    return Scaffold(
      appBar: AppBar(title: const Text('Book Details')),
      body: bookAsync.when(
        data: (book) {
          if (book == null) {
            return const Center(child: Text('Book not found.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(book.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(book.author ?? 'Unknown author'),
              const SizedBox(height: 8),
              Text('Format: ${book.format.toUpperCase()}'),
              const SizedBox(height: 8),
              Text('File: ${book.filePath}'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.readerPath(book.id)),
                icon: const Icon(Icons.chrome_reader_mode),
                label: const Text('Start Reading'),
              ),
              const SizedBox(height: 24),
              Text('Table of Contents',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (book.chapters.isEmpty)
                const Text('TOC not extracted yet.')
              else
                ...book.chapters.map(
                  (chapter) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(chapter.title),
                    subtitle: Text('Chapter ${chapter.index + 1}'),
                  ),
                ),
            ],
          );
        },
        error: (error, _) => Center(child: Text('Failed to load book: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
