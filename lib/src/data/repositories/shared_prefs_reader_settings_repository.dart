import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/reader_settings.dart';
import '../../domain/repositories/reader_settings_repository.dart';

class SharedPrefsReaderSettingsRepository implements ReaderSettingsRepository {
  static const _fontSizeKey = 'reader_font_size';
  static const _pageMarginKey = 'reader_page_margin';
  static const _themeKey = 'reader_theme';

  @override
  Future<ReaderSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? ReaderTheme.system.index;

    return ReaderSettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 18,
      pageMargin: prefs.getDouble(_pageMarginKey) ?? 16,
      theme: ReaderTheme.values[themeIndex],
    );
  }

  @override
  Future<void> saveSettings(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, settings.fontSize);
    await prefs.setDouble(_pageMarginKey, settings.pageMargin);
    await prefs.setInt(_themeKey, settings.theme.index);
  }
}
