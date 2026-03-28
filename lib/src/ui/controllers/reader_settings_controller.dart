import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reader_settings.dart';
import '../providers/app_providers.dart';

final readerSettingsControllerProvider =
    AsyncNotifierProvider<ReaderSettingsController, ReaderSettings>(
  ReaderSettingsController.new,
);

class ReaderSettingsController extends AsyncNotifier<ReaderSettings> {
  @override
  Future<ReaderSettings> build() async {
    return ref.read(readerSettingsRepositoryProvider).getSettings();
  }

  Future<void> updateFontSize(double value) async {
    final current = state.value ?? const ReaderSettings();
    final updated = current.copyWith(fontSize: value);
    state = AsyncData(updated);
    await ref.read(readerSettingsRepositoryProvider).saveSettings(updated);
  }

  Future<void> updatePageMargin(double value) async {
    final current = state.value ?? const ReaderSettings();
    final updated = current.copyWith(pageMargin: value);
    state = AsyncData(updated);
    await ref.read(readerSettingsRepositoryProvider).saveSettings(updated);
  }

  Future<void> updateTheme(ReaderTheme theme) async {
    final current = state.value ?? const ReaderSettings();
    final updated = current.copyWith(theme: theme);
    state = AsyncData(updated);
    await ref.read(readerSettingsRepositoryProvider).saveSettings(updated);
  }
}
