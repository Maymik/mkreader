import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/book.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/chapter.dart';
import '../../domain/models/reader_settings.dart';
import '../../domain/models/reading_progress.dart';
import '../controllers/bookmark_controller.dart';
import '../controllers/library_controller.dart';
import '../controllers/reader_settings_controller.dart';
import '../controllers/reading_progress_controller.dart';
import '../controllers/simple_text_paginator.dart';
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
  int _currentPageIndex = 0;
  int _currentPageCount = 1;

  double? _pendingRestoreChapterProgress;
  int? _pendingStoredPageIndex;
  int? _pendingStoredPageCount;
  String? _lastPaginationSignature;
  List<Chapter> _activeChapters = const [];
  int _lastKnownTotalPages = 1;
  String? _precomputeRunningForEnvironment;

  final Map<_ChapterPaginationCacheKey, List<String>> _chapterPagesCache = {};
  final Map<_ChapterLayoutCacheKey, int> _chapterPageCountCache = {};
  final Map<String, String> _chapterTextCache = {};
  String _currentPageText = '';

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
      _initializeProgress(progress, chapters.length);
    }

    final chapter = chapters[_currentChapterIndex];
    final chapterRequest = (
      epubPath: book.filePath,
      chapterHref: chapter.href,
    );
    final chapterTextAsync = ref.watch(chapterTextProvider(chapterRequest));
    if (chapterTextAsync.hasValue) {
      final loadedText = chapterTextAsync.valueOrNull ?? '';
      _chapterTextCache[chapter.id] = loadedText;
    }
    final currentChapterText =
        _chapterTextCache[chapter.id] ?? chapterTextAsync.valueOrNull;

    final colors = _readerColors(settings.theme, Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            onPressed: () => _addBookmark(context),
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Add bookmark',
          ),
          IconButton(
            onPressed: () => _showBookmarksSheet(context),
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Bookmarks',
          ),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.foreground,
                  ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: currentChapterText == null
                  ? chapterTextAsync.when(
                      data: (_) => const SizedBox.shrink(),
                      error: (error, _) => Center(
                        child: Text(
                          'Failed to load chapter: $error',
                          style: TextStyle(color: colors.foreground),
                        ),
                      ),
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final textStyle = TextStyle(
                          fontSize: settings.fontSize,
                          height: 1.6,
                          color: colors.foreground,
                        );

                        final pages = _getOrCreatePages(
                          chapter: chapter,
                          chapterText: currentChapterText,
                          fontSize: settings.fontSize,
                          pageMargin: settings.pageMargin,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          textStyle: textStyle,
                        );

                        final signature = _paginationSignature(
                          chapterId: chapter.id,
                          chapterText: currentChapterText,
                          fontSize: settings.fontSize,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                        );
                        final pageIndex = _resolveCurrentPageIndex(
                          signature: signature,
                          pageCount: pages.length,
                        );

                        final environmentKey = _buildEnvironmentKey(
                          fontSize: settings.fontSize,
                          pageMargin: settings.pageMargin,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                        );
                        _prefetchAdjacentChapterTexts(
                          chapters: chapters,
                          book: book,
                          centerIndex: _currentChapterIndex,
                        );
                        _precomputePageCountsIfNeeded(
                          chapters: chapters,
                          book: book,
                          textStyle: textStyle,
                          fontSize: settings.fontSize,
                          pageMargin: settings.pageMargin,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          environmentKey: environmentKey,
                        );

                        final globalPageStats = _computeGlobalPageStats(
                          chapters: chapters,
                          fontSize: settings.fontSize,
                          pageMargin: settings.pageMargin,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                        );

                        final pageText =
                            (pages.isEmpty || pages[pageIndex].trim().isEmpty)
                                ? null
                                : pages[pageIndex];
                        _currentPageText = pageText ?? '';

                        return Column(
                          children: [
                            Expanded(
                              child: pageText == null
                                  ? Center(
                                      child: Text(
                                        'Chapter is empty.',
                                        style: TextStyle(
                                          color: colors.foreground,
                                        ),
                                      ),
                                    )
                                  : Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(pageText, style: textStyle),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _goToPreviousPage(chapters.length),
                                  child: const Text('Previous'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () =>
                                      _goToNextPage(chapters.length),
                                  child: const Text('Next'),
                                ),
                                const Spacer(),
                                Text(
                                  'Page ${globalPageStats.currentPage} of ${globalPageStats.totalPages}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.foreground),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _initializeProgress(ReadingProgress? progress, int chapterCount) {
    _currentChapterIndex =
        (progress?.chapterIndex ?? 0).clamp(0, chapterCount - 1);
    final storedPage = _StoredPageProgress.tryParse(progress?.cfi);

    _pendingRestoreChapterProgress = storedPage?.chapterProgress ??
        progress?.progression.clamp(0.0, 1.0) ??
        0;
    _pendingStoredPageIndex = storedPage?.pageIndex;
    _pendingStoredPageCount = storedPage?.pageCount;

    _currentPageIndex = 0;
    _currentPageCount = 1;
    _lastPaginationSignature = null;
    _progressInitialized = true;
  }

  int _resolveCurrentPageIndex({
    required String signature,
    required int pageCount,
  }) {
    final safePageCount = pageCount <= 0 ? 1 : pageCount;

    if (_lastPaginationSignature != signature) {
      final oldProgress = _currentPageCount <= 1
          ? 0.0
          : (_currentPageIndex / (_currentPageCount - 1)).clamp(0.0, 1.0);

      final restoredFromStoredPage = _restoredProgressFromStoredPage();
      final targetProgress = (restoredFromStoredPage ??
              _pendingRestoreChapterProgress ??
              oldProgress)
          .clamp(0.0, 1.0);

      _currentPageCount = safePageCount;
      _currentPageIndex = (targetProgress * (_currentPageCount - 1)).round();
      _currentPageIndex = _currentPageIndex.clamp(0, _currentPageCount - 1);

      _pendingRestoreChapterProgress = null;
      _pendingStoredPageIndex = null;
      _pendingStoredPageCount = null;
      _lastPaginationSignature = signature;
    } else {
      _currentPageCount = safePageCount;
      _currentPageIndex = _currentPageIndex.clamp(0, _currentPageCount - 1);
    }

    return _currentPageIndex;
  }

  String _paginationSignature({
    required String chapterId,
    required String chapterText,
    required double fontSize,
    required double width,
    required double height,
  }) {
    return [
      chapterId,
      chapterText.hashCode,
      fontSize.toStringAsFixed(2),
      width.floor(),
      height.floor(),
    ].join('|');
  }

  Future<void> _goToNextPage(int chapterCount) async {
    if (_currentPageIndex < _currentPageCount - 1) {
      setState(() {
        _currentPageIndex++;
      });
      return;
    }

    if (_currentChapterIndex >= chapterCount - 1) {
      return;
    }

    await _persistCurrentProgress();
    if (!mounted) {
      return;
    }

    setState(() {
      _currentChapterIndex++;
      _currentPageIndex = 0;
      _currentPageCount = 1;
      _lastPaginationSignature = null;
      _pendingRestoreChapterProgress = 0;
      _pendingStoredPageIndex = null;
      _pendingStoredPageCount = null;
    });
  }

  Future<void> _goToPreviousPage(int chapterCount) async {
    if (_currentPageIndex > 0) {
      setState(() {
        _currentPageIndex--;
      });
      return;
    }

    if (_currentChapterIndex <= 0 || chapterCount <= 0) {
      return;
    }

    await _persistCurrentProgress();
    if (!mounted) {
      return;
    }

    setState(() {
      _currentChapterIndex--;
      _currentPageIndex = 0;
      _currentPageCount = 1;
      _lastPaginationSignature = null;
      _pendingRestoreChapterProgress = 1.0;
      _pendingStoredPageIndex = null;
      _pendingStoredPageCount = null;
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
      await _persistCurrentProgress();
      if (!mounted) {
        return;
      }

      setState(() {
        _currentChapterIndex = selectedIndex;
        _currentPageIndex = 0;
        _currentPageCount = 1;
        _pendingRestoreChapterProgress = 0;
        _pendingStoredPageIndex = null;
        _pendingStoredPageCount = null;
        _lastPaginationSignature = null;
      });
    }
  }

  Future<void> _addBookmark(BuildContext context) async {
    if (_activeChapters.isEmpty) {
      return;
    }

    final safeChapterIndex =
        _currentChapterIndex.clamp(0, _activeChapters.length - 1);
    final chapter = _activeChapters[safeChapterIndex];
    final chapterProgress = _currentPageCount <= 1
        ? 0.0
        : (_currentPageIndex / (_currentPageCount - 1)).clamp(0.0, 1.0);
    final marker = _StoredPageProgress(
      pageIndex: _currentPageIndex,
      pageCount: _currentPageCount,
      chapterProgress: chapterProgress,
    );

    final bookmark = Bookmark(
      id: 'bm_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      bookId: widget.bookId,
      chapterId: chapter.id,
      chapterIndex: safeChapterIndex,
      positionCfi: marker.toJsonString(),
      note: _buildBookmarkSnippet(chapter),
      createdAt: DateTime.now(),
    );

    final error =
        await ref.read(bookmarkControllerProvider).addBookmark(bookmark);
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Bookmark added'),
      ),
    );
  }

  Future<void> _showBookmarksSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final bookmarksAsync = ref.watch(
              bookmarksForBookProvider(widget.bookId),
            );

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: bookmarksAsync.when(
                data: (bookmarks) {
                  if (bookmarks.isEmpty) {
                    return const Center(
                      child: Text('No bookmarks yet.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final bookmark = bookmarks[index];
                      final marker =
                          _StoredPageProgress.tryParse(bookmark.positionCfi);
                      final pageLabel = marker == null
                          ? ''
                          : 'Page ${marker.pageIndex + 1}/${marker.pageCount}';

                      return ListTile(
                        title: Text(
                          bookmark.note ??
                              'Chapter ${bookmark.chapterIndex + 1}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          pageLabel.isEmpty
                              ? 'Chapter ${bookmark.chapterIndex + 1}'
                              : 'Chapter ${bookmark.chapterIndex + 1} • $pageLabel',
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _jumpToBookmark(bookmark);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete bookmark',
                          onPressed: () async {
                            final error = await ref
                                .read(bookmarkControllerProvider)
                                .deleteBookmark(
                                  bookmarkId: bookmark.id,
                                  bookId: widget.bookId,
                                );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(error ?? 'Bookmark deleted'),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
                error: (error, _) => Center(
                  child: Text('Failed to load bookmarks: $error'),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _jumpToBookmark(Bookmark bookmark) async {
    if (_activeChapters.isEmpty) {
      return;
    }

    final targetChapterIndex =
        bookmark.chapterIndex.clamp(0, _activeChapters.length - 1);
    final marker = _StoredPageProgress.tryParse(bookmark.positionCfi);

    await _persistCurrentProgress();
    if (!mounted) {
      return;
    }

    setState(() {
      _currentChapterIndex = targetChapterIndex;
      _currentPageIndex = 0;
      _currentPageCount = 1;
      _lastPaginationSignature = null;
      _pendingRestoreChapterProgress = marker?.chapterProgress ?? 0;
      _pendingStoredPageIndex = marker?.pageIndex;
      _pendingStoredPageCount = marker?.pageCount;
    });
  }

  String _buildBookmarkSnippet(Chapter chapter) {
    final normalized = _currentPageText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return chapter.title;
    }
    const maxLen = 100;
    if (normalized.length <= maxLen) {
      return normalized;
    }
    return '${normalized.substring(0, maxLen)}...';
  }

  List<String> _getOrCreatePages({
    required Chapter chapter,
    required String chapterText,
    required double fontSize,
    required double pageMargin,
    required double maxWidth,
    required double maxHeight,
    required TextStyle textStyle,
  }) {
    final environmentKey = _buildEnvironmentKey(
      fontSize: fontSize,
      pageMargin: pageMargin,
      width: maxWidth,
      height: maxHeight,
    );
    final cacheKey = _ChapterPaginationCacheKey(
      chapterId: chapter.id,
      environmentKey: environmentKey,
      textHash: chapterText.hashCode,
    );
    final cached = _chapterPagesCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final pages = SimpleTextPaginator.paginate(
      text: chapterText,
      style: textStyle,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    _chapterPagesCache[cacheKey] = pages;
    _chapterPageCountCache[_ChapterLayoutCacheKey(
      chapterId: chapter.id,
      environmentKey: environmentKey,
    )] = pages.isEmpty ? 1 : pages.length;
    return pages;
  }

  String _buildEnvironmentKey({
    required double fontSize,
    required double pageMargin,
    required double width,
    required double height,
  }) {
    return '${fontSize.toStringAsFixed(2)}|${pageMargin.toStringAsFixed(2)}|${width.floor()}|${height.floor()}';
  }

  void _prefetchAdjacentChapterTexts({
    required List<Chapter> chapters,
    required Book book,
    required int centerIndex,
  }) {
    for (final adjacentIndex in [centerIndex - 1, centerIndex + 1]) {
      if (adjacentIndex < 0 || adjacentIndex >= chapters.length) {
        continue;
      }
      final chapter = chapters[adjacentIndex];
      if (_chapterTextCache.containsKey(chapter.id)) {
        continue;
      }

      final request = (
        epubPath: book.filePath,
        chapterHref: chapter.href,
      );
      unawaited(
        ref.read(chapterTextProvider(request).future).then((text) {
          _chapterTextCache[chapter.id] = text;
        }).catchError((_) {}),
      );
    }
  }

  void _precomputePageCountsIfNeeded({
    required List<Chapter> chapters,
    required Book book,
    required TextStyle textStyle,
    required double fontSize,
    required double pageMargin,
    required double maxWidth,
    required double maxHeight,
    required String environmentKey,
  }) {
    if (_precomputeRunningForEnvironment == environmentKey) {
      return;
    }

    final hasUnknownChapter = chapters.any((chapter) {
      return !_chapterPageCountCache.containsKey(
        _ChapterLayoutCacheKey(
          chapterId: chapter.id,
          environmentKey: environmentKey,
        ),
      );
    });
    if (!hasUnknownChapter) {
      return;
    }

    _precomputeRunningForEnvironment = environmentKey;
    unawaited(() async {
      try {
        for (final chapter in chapters) {
          if (!_chapterPageCountCache.containsKey(
            _ChapterLayoutCacheKey(
              chapterId: chapter.id,
              environmentKey: environmentKey,
            ),
          )) {
            var chapterText = _chapterTextCache[chapter.id];
            if (chapterText == null) {
              try {
                final loadedChapterText = await ref.read(
                  chapterTextProvider((
                    epubPath: book.filePath,
                    chapterHref: chapter.href,
                  )).future,
                );
                chapterText = loadedChapterText;
                _chapterTextCache[chapter.id] = loadedChapterText;
              } catch (_) {
                // Keep a conservative fallback count when chapter text cannot be loaded now.
                _chapterPageCountCache[_ChapterLayoutCacheKey(
                  chapterId: chapter.id,
                  environmentKey: environmentKey,
                )] = 1;
                continue;
              }
            }
            _getOrCreatePages(
              chapter: chapter,
              chapterText: chapterText,
              fontSize: fontSize,
              pageMargin: pageMargin,
              maxWidth: maxWidth,
              maxHeight: maxHeight,
              textStyle: textStyle,
            );
          }
        }
      } finally {
        _precomputeRunningForEnvironment = null;
        if (mounted) {
          setState(() {});
        }
      }
    }());
  }

  _GlobalPageStats _computeGlobalPageStats({
    required List<Chapter> chapters,
    required double fontSize,
    required double pageMargin,
    required double maxWidth,
    required double maxHeight,
  }) {
    final environmentKey = _buildEnvironmentKey(
      fontSize: fontSize,
      pageMargin: pageMargin,
      width: maxWidth,
      height: maxHeight,
    );

    var totalPages = 0;
    var pagesBeforeCurrent = 0;

    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final pageCountForChapter = index == _currentChapterIndex
          ? _currentPageCount
          : (_chapterPageCountCache[_ChapterLayoutCacheKey(
                chapterId: chapter.id,
                environmentKey: environmentKey,
              )] ??
              1);

      if (index < _currentChapterIndex) {
        pagesBeforeCurrent += pageCountForChapter;
      }
      totalPages += pageCountForChapter;
    }

    if (totalPages > 0) {
      _lastKnownTotalPages = totalPages;
    }
    final safeTotalPages = totalPages <= 0 ? _lastKnownTotalPages : totalPages;
    final currentGlobalPage =
        (pagesBeforeCurrent + _currentPageIndex + 1).clamp(1, safeTotalPages);
    return _GlobalPageStats(
      currentPage: currentGlobalPage,
      totalPages: safeTotalPages <= 0 ? 1 : safeTotalPages,
    );
  }

  double? _restoredProgressFromStoredPage() {
    if (_pendingStoredPageIndex == null || _pendingStoredPageCount == null) {
      return null;
    }
    if (_pendingStoredPageCount! <= 1) {
      return 0;
    }
    return (_pendingStoredPageIndex! / (_pendingStoredPageCount! - 1))
        .clamp(0.0, 1.0);
  }

  Future<void> _persistCurrentProgress() async {
    if (_activeChapters.isEmpty) {
      return;
    }

    final safeChapterIndex =
        _currentChapterIndex.clamp(0, _activeChapters.length - 1);
    final chapter = _activeChapters[safeChapterIndex];

    final chapterProgress = _currentPageCount <= 1
        ? 0.0
        : (_currentPageIndex / (_currentPageCount - 1)).clamp(0.0, 1.0);

    final marker = _StoredPageProgress(
      pageIndex: _currentPageIndex,
      pageCount: _currentPageCount,
      chapterProgress: chapterProgress,
    );

    final progress = ReadingProgress(
      bookId: widget.bookId,
      chapterId: chapter.id,
      chapterIndex: safeChapterIndex,
      progression: chapterProgress,
      cfi: marker.toJsonString(),
      updatedAt: DateTime.now(),
    );

    await ref.read(readingProgressControllerProvider).saveProgress(progress);
  }

  Scaffold _buildStatusScaffold(String message) {
    return Scaffold(
      appBar: const _ReaderAppBar(title: 'Reader'),
      body: Center(child: Text(message)),
    );
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

class _StoredPageProgress {
  const _StoredPageProgress({
    required this.pageIndex,
    required this.pageCount,
    required this.chapterProgress,
  });

  final int pageIndex;
  final int pageCount;
  final double chapterProgress;

  String toJsonString() {
    return jsonEncode({
      'pageIndex': pageIndex,
      'pageCount': pageCount,
      'chapterProgress': chapterProgress,
    });
  }

  static _StoredPageProgress? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final pageIndex = decoded['pageIndex'];
      final pageCount = decoded['pageCount'];
      final chapterProgress = decoded['chapterProgress'];

      if (pageIndex is! num || pageCount is! num || chapterProgress is! num) {
        return null;
      }

      return _StoredPageProgress(
        pageIndex: pageIndex.toInt(),
        pageCount: pageCount.toInt(),
        chapterProgress: chapterProgress.toDouble().clamp(0.0, 1.0),
      );
    } catch (_) {
      // TODO: Migrate legacy progress markers if old formats are introduced.
      return null;
    }
  }
}

class _GlobalPageStats {
  const _GlobalPageStats({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;
}

class _ChapterPaginationCacheKey {
  const _ChapterPaginationCacheKey({
    required this.chapterId,
    required this.environmentKey,
    required this.textHash,
  });

  final String chapterId;
  final String environmentKey;
  final int textHash;

  @override
  bool operator ==(Object other) {
    return other is _ChapterPaginationCacheKey &&
        other.chapterId == chapterId &&
        other.environmentKey == environmentKey &&
        other.textHash == textHash;
  }

  @override
  int get hashCode => Object.hash(chapterId, environmentKey, textHash);
}

class _ChapterLayoutCacheKey {
  const _ChapterLayoutCacheKey({
    required this.chapterId,
    required this.environmentKey,
  });

  final String chapterId;
  final String environmentKey;

  @override
  bool operator ==(Object other) {
    return other is _ChapterLayoutCacheKey &&
        other.chapterId == chapterId &&
        other.environmentKey == environmentKey;
  }

  @override
  int get hashCode => Object.hash(chapterId, environmentKey);
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
