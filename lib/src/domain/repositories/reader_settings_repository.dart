import '../models/reader_settings.dart';

abstract class ReaderSettingsRepository {
  Future<ReaderSettings> getSettings();
  Future<void> saveSettings(ReaderSettings settings);
}
