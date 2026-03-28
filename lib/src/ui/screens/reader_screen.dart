import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reading_progress.dart';
import '../controllers/library_controller.dart';
import '../controllers/reader_settings_controller.dart';
import '../controllers/reading_progress_controller.dart';
import '../providers/app_providers.dart';

typedef ChapterTextRequest = ({String epubPath, String chapterHref});

final chapterTextProvider =
    FutureProvider.family<String, ChapterTextRequest>((ref, request) {
  return ref.read(epubContentServiceProvider).extractChapterText(
        epubPath: request.epubPath,
        chapterHref: request.chapterHref,
      );
});

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _progressInitialized = false;
  int _currentChapterIndex = 0;
  List<Chapter> _activeChapters = const [];

  @override
  void dispose() {
    unawaited(_persistCurrentProgress());
    super.dispose();
  }

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

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_persistCurrentProgress());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(book.title),
        ),
        body: _buildReaderBody(
          context,
          book,
          settings.fontSize,
          settings.pageMargin,
          progress,
        ),
      ),
    );
  }

  Widget _buildReaderBody(
    BuildContext context,
    Book book,
    double fontSize,
    double pageMargin,
    ReadingProgress? progress,
  ) {
    final chapters = book.chapters;
    _activeChapters = chapters;

    if (chapters.isEmpty) {
      return const Center(child: Text('No chapters available yet.'));
    }

    if (!_progressInitialized) {
      _currentChapterIndex =
          (progress?.chapterIndex ?? 0).clamp(0, chapters.length - 1);
      _progressInitialized = true;
    }

    final chapter = chapters[_currentChapterIndex];
    final chapterTextAsync = ref.watch(
      chapterTextProvider((
        epubPath: book.filePath,
        chapterHref: chapter.href,
      )),
    );

    return Padding(
      padding: EdgeInsets.all(pageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chapter.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Expanded(
            child: chapterTextAsync.when(
              data: (text) => SingleChildScrollView(
                child: Text(
                  text,
                  style: TextStyle(fontSize: fontSize, height: 1.5),
                ),
              ),
              error: (error, _) => Text(
                'Failed to load chapter: $error',
                style: TextStyle(fontSize: fontSize),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 12),
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
                  await _persistCurrentProgress();
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

  Future<void> _persistCurrentProgress() async {
    if (_activeChapters.isEmpty) {
      return;
    }

    final safeIndex = _currentChapterIndex.clamp(0, _activeChapters.length - 1);
    final chapter = _activeChapters[safeIndex];
    final progress = ReadingProgress(
      bookId: widget.bookId,
      chapterId: chapter.id,
      chapterIndex: safeIndex,
      progression: (safeIndex + 1) / _activeChapters.length,
      updatedAt: DateTime.now(),
    );

    await ref.read(readingProgressControllerProvider).saveProgress(progress);
  }
}
