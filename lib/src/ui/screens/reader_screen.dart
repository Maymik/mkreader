import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chapter.dart';
import '../../domain/models/reading_progress.dart';
import '../controllers/library_controller.dart';
import '../controllers/reader_settings_controller.dart';
import '../controllers/reading_progress_controller.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _progressInitialized = false;
  int _currentChapterIndex = 0;

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookByIdProvider(widget.bookId));
    final settingsAsync = ref.watch(readerSettingsControllerProvider);
    final progressAsync = ref.watch(readingProgressProvider(widget.bookId));

    if (bookAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: Center(child: Text('Book error: ${bookAsync.error}')),
      );
    }
    if (settingsAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: Center(child: Text('Settings error: ${settingsAsync.error}')),
      );
    }
    if (progressAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: Center(child: Text('Progress error: ${progressAsync.error}')),
      );
    }
    if (bookAsync.isLoading ||
        settingsAsync.isLoading ||
        progressAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final book = bookAsync.valueOrNull;
    final settings = settingsAsync.valueOrNull;
    final progress = progressAsync.valueOrNull;

    if (book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: const Center(child: Text('Book not found.')),
      );
    }
    if (settings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reader')),
        body: const Center(child: Text('Settings unavailable.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
      ),
      body: _buildReaderBody(
        context,
        book.chapters,
        settings.fontSize,
        settings.pageMargin,
        progress,
      ),
    );
  }

  Widget _buildReaderBody(
    BuildContext context,
    List<Chapter> chapters,
    double fontSize,
    double pageMargin,
    ReadingProgress? progress,
  ) {
    if (chapters.isEmpty) {
      return const Center(child: Text('No chapters available yet.'));
    }

    if (!_progressInitialized && progress != null) {
      _currentChapterIndex =
          progress.chapterIndex.clamp(0, chapters.length - 1);
      _progressInitialized = true;
    }

    final chapter = chapters[_currentChapterIndex];

    return Padding(
      padding: EdgeInsets.all(pageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chapter.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'EPUB rendering placeholder.\n\n'
            'TODO: plug in a real EPUB renderer and CFI-based position tracking.\n'
            'Current chapter href: ${chapter.href}',
            style: TextStyle(fontSize: fontSize),
          ),
          const Spacer(),
          Row(
            children: [
              OutlinedButton(
                onPressed: _currentChapterIndex == 0
                    ? null
                    : () => setState(() => _currentChapterIndex--),
                child: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _currentChapterIndex >= chapters.length - 1
                    ? null
                    : () => setState(() => _currentChapterIndex++),
                child: const Text('Next'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final saveProgress = ReadingProgress(
                    bookId: widget.bookId,
                    chapterId: chapter.id,
                    chapterIndex: _currentChapterIndex,
                    progression: (_currentChapterIndex + 1) / chapters.length,
                    updatedAt: DateTime.now(),
                  );
                  await ref
                      .read(readingProgressControllerProvider)
                      .saveProgress(saveProgress);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reading position saved')),
                  );
                },
                child: const Text('Save Position'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
