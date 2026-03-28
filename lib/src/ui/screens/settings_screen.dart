import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reader_settings.dart';
import '../controllers/reader_settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(readerSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reader Settings')),
      body: settingsAsync.when(
        data: (settings) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Font Size: ${settings.fontSize.toStringAsFixed(0)}'),
              Slider(
                min: 12,
                max: 32,
                divisions: 20,
                value: settings.fontSize,
                onChanged: (value) => ref
                    .read(readerSettingsControllerProvider.notifier)
                    .updateFontSize(value),
              ),
              const SizedBox(height: 16),
              Text('Page Margin: ${settings.pageMargin.toStringAsFixed(0)}'),
              Slider(
                min: 8,
                max: 40,
                divisions: 16,
                value: settings.pageMargin,
                onChanged: (value) => ref
                    .read(readerSettingsControllerProvider.notifier)
                    .updatePageMargin(value),
              ),
              const SizedBox(height: 16),
              const Text('Theme'),
              const SizedBox(height: 8),
              ...ReaderTheme.values.map(
                (theme) => RadioListTile<ReaderTheme>(
                  value: theme,
                  groupValue: settings.theme,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    ref
                        .read(readerSettingsControllerProvider.notifier)
                        .updateTheme(value);
                  },
                  title: Text(theme.name),
                ),
              ),
            ],
          );
        },
        error: (error, _) =>
            Center(child: Text('Failed to load settings: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
