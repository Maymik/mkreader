import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../domain/models/reader_settings.dart';
import '../ui/controllers/reader_settings_controller.dart';

class MkReaderApp extends ConsumerWidget {
  const MkReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(readerSettingsControllerProvider);
    final settings = settingsAsync.value ?? const ReaderSettings();

    return MaterialApp.router(
      title: 'MK Reader',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      themeMode: _mapThemeMode(settings.theme),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
      ),
    );
  }

  ThemeMode _mapThemeMode(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return ThemeMode.light;
      case ReaderTheme.dark:
        return ThemeMode.dark;
      case ReaderTheme.sepia:
        // TODO: Add dedicated sepia theme extension.
        return ThemeMode.light;
      case ReaderTheme.system:
        return ThemeMode.system;
    }
  }
}
