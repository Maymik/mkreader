import 'package:go_router/go_router.dart';

import '../../ui/screens/book_details_screen.dart';
import '../../ui/screens/library_screen.dart';
import '../../ui/screens/reader_screen.dart';
import '../../ui/screens/settings_screen.dart';

abstract final class AppRoutes {
  static const library = '/';
  static const bookDetails = '/book/:bookId';
  static const reader = '/reader/:bookId';
  static const settings = '/settings';

  static String bookDetailsPath(String bookId) =>
      '/book/${Uri.encodeComponent(bookId)}';
  static String readerPath(String bookId) =>
      '/reader/${Uri.encodeComponent(bookId)}';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.library,
  routes: [
    GoRoute(
      path: AppRoutes.library,
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: AppRoutes.bookDetails,
      builder: (context, state) {
        final bookId = Uri.decodeComponent(state.pathParameters['bookId']!);
        return BookDetailsScreen(bookId: bookId);
      },
    ),
    GoRoute(
      path: AppRoutes.reader,
      builder: (context, state) {
        final bookId = Uri.decodeComponent(state.pathParameters['bookId']!);
        return ReaderScreen(bookId: bookId);
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
