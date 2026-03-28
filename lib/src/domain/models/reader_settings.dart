enum ReaderTheme {
  light,
  dark,
  sepia,
  system,
}

class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 18,
    this.pageMargin = 16,
    this.theme = ReaderTheme.system,
  });

  final double fontSize;
  final double pageMargin;
  final ReaderTheme theme;

  ReaderSettings copyWith({
    double? fontSize,
    double? pageMargin,
    ReaderTheme? theme,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      pageMargin: pageMargin ?? this.pageMargin,
      theme: theme ?? this.theme,
    );
  }
}
