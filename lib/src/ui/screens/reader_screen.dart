import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reader_settings.dart';
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
  final ScrollController _scrollController = ScrollController();

  bool _progressInitialized = false;
  int _currentChapterIndex = 0;
  int _restoredForChapterIndex = -1;
  double? _pendingRestoreProgress;
  double _inChapterProgress = 0;
  List<Chapter> _activeChapters = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) {
        return;
      }
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) {
        _inChapterProgress = 0;
        return;
      }
      _inChapterProgress =
          (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    unawaited(_persistCurrentProgress());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookByIdProvider(widget.bookId));
    final settingsAsync = ref.watch(readerSettingsControllerProvider);
    final progressAsync = ref.watch(readingProgressProvider(widget.bookId));

    if (bookAsync.hasError) {
      return _buildStatusScaffold('Book error: ${bookAsync.error}');
    }
    if (settingsAsync.hasError) {
      return _buildStatusScaffold('Settings error: ${settingsAsync.error}');
    }
    if (progressAsync.hasError) {
      return _buildStatusScaffold('Progress error: ${progressAsync.error}');
    }
    if (bookAsync.isLoading ||
        settingsAsync.isLoading ||
        progressAsync.isLoading) {
      return const Scaffold(
        appBar: _ReaderAppBar(title: 'Reader'),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final book = bookAsync.valueOrNull;
    final settings = settingsAsync.valueOrNull;
    final progress = progressAsync.valueOrNull;

    if (book == null) {
      return _buildStatusScaffold('Book not found.');
    }
    if (settings == null) {
      return _buildStatusScaffold('Settings unavailable.');
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_persistCurrentProgress());
        }
      },
      child: _buildReaderScaffold(context, book, settings, progress),
    );
  }

  Scaffold _buildReaderScaffold(
    BuildContext context,
    Book book,
    ReaderSettings settings,
    ReadingProgress? progress,
  ) {
    final chapters = book.chapters;
    _activeChapters = chapters;

    if (chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: const Center(child: Text('No chapters available yet.')),
      );
    }

    if (!_progressInitialized) {
      _currentChapterIndex =
          (progress?.chapterIndex ?? 0).clamp(0, chapters.length - 1);
      _pendingRestoreProgress = (progress?.progression ?? 0).clamp(0.0, 1.0);
      _progressInitialized = true;
    }

    final chapter = chapters[_currentChapterIndex];
    final chapterTextAsync = ref.watch(
      chapterTextProvider((
        epubPath: book.filePath,
        chapterHref: chapter.href,
      )),
    );

    final colors = _readerColors(settings.theme, Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            onPressed: () => _showTableOfContents(context, chapters),
            icon: const Icon(Icons.list),
            tooltip: 'Table of contents',
          ),
        ],
      ),
      body: Container(
        color: colors.background,
        padding: EdgeInsets.all(settings.pageMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: colors.foreground),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: chapterTextAsync.when(
                data: (text) {
                  _restoreScrollIfNeeded();
                  if (text.trim().isEmpty) {
                    return Center(
                      child: Text(
                        'Chapter is empty.',
                        style: TextStyle(color: colors.foreground),
                      ),
                    );
                  }
                  return Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: settings.fontSize,
                          height: 1.6,
                          color: colors.foreground,
                        ),
                      ),
                    ),
                  );
                },
                error: (error, _) => Center(
                  child: Text(
                    'Failed to load chapter: $error',
                    style: TextStyle(color: colors.foreground),
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _currentChapterIndex == 0
                      ? null
                      : () => _changeChapter(_currentChapterIndex - 1),
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _currentChapterIndex >= chapters.length - 1
                      ? null
                      : () => _changeChapter(_currentChapterIndex + 1),
                  child: const Text('Next'),
                ),
                const Spacer(),
                Text(
                  '${_currentChapterIndex + 1}/${chapters.length}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.foreground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Scaffold _buildStatusScaffold(String message) {
    return Scaffold(
      appBar: const _ReaderAppBar(title: 'Reader'),
      body: Center(child: Text(message)),
    );
  }

  void _restoreScrollIfNeeded() {
    if (_restoredForChapterIndex == _currentChapterIndex) {
      return;
    }

    _restoredForChapterIndex = _currentChapterIndex;
    final restoreProgress = (_pendingRestoreProgress ?? 0).clamp(0.0, 1.0);
    _pendingRestoreProgress = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      final targetOffset = maxExtent * restoreProgress;
      _scrollController.jumpTo(targetOffset.clamp(0.0, maxExtent));
      _inChapterProgress = maxExtent <= 0
          ? 0
          : (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    });
  }

  Future<void> _showTableOfContents(
    BuildContext context,
    List<Chapter> chapters,
  ) async {
    if (chapters.isEmpty) {
      return;
    }

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return ListTile(
                selected: index == _currentChapterIndex,
                title: Text(chapter.title),
                subtitle: Text('Chapter ${index + 1}'),
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );

    if (selectedIndex != null && selectedIndex != _currentChapterIndex) {
      await _changeChapter(selectedIndex);
    }
  }

  Future<void> _changeChapter(int newIndex) async {
    await _persistCurrentProgress();
    if (!mounted) {
      return;
    }

    setState(() {
      _currentChapterIndex = newIndex;
      _pendingRestoreProgress = 0;
      _restoredForChapterIndex = -1;
      _inChapterProgress = 0;
    });
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
      progression: _inChapterProgress.clamp(0.0, 1.0),
      updatedAt: DateTime.now(),
    );

    await ref.read(readingProgressControllerProvider).saveProgress(progress);
  }

  _ReaderColors _readerColors(
      ReaderTheme readerTheme, Brightness appBrightness) {
    final effectiveTheme = readerTheme == ReaderTheme.system
        ? (appBrightness == Brightness.dark
            ? ReaderTheme.dark
            : ReaderTheme.light)
        : readerTheme;

    switch (effectiveTheme) {
      case ReaderTheme.light:
        return const _ReaderColors(
          background: Color(0xFFFAFAFA),
          foreground: Color(0xFF111111),
        );
      case ReaderTheme.dark:
        return const _ReaderColors(
          background: Color(0xFF121212),
          foreground: Color(0xFFECECEC),
        );
      case ReaderTheme.sepia:
        return const _ReaderColors(
          background: Color(0xFFF4ECD8),
          foreground: Color(0xFF3A2F1F),
        );
      case ReaderTheme.system:
        return const _ReaderColors(
          background: Color(0xFFFAFAFA),
          foreground: Color(0xFF111111),
        );
    }
  }
}

class _ReaderColors {
  const _ReaderColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

class _ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ReaderAppBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text(title));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
