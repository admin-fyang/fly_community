/// 主题模式：日间 / 夜间 / 跟随系统
enum ThemeModeType {
  light,
  dark,
  system;

  /// 循环切换顺序：日间 → 夜间 → 跟随系统 → 日间
  ThemeModeType get next {
    switch (this) {
      case ThemeModeType.light:
        return ThemeModeType.dark;
      case ThemeModeType.dark:
        return ThemeModeType.system;
      case ThemeModeType.system:
        return ThemeModeType.light;
    }
  }

  /// 模式的中文展示名(用于切换按钮 tooltip 等)
  String get label {
    switch (this) {
      case ThemeModeType.light:
        return '日间模式';
      case ThemeModeType.dark:
        return '夜间模式';
      case ThemeModeType.system:
        return '跟随系统';
    }
  }

  /// 主题设置页面使用原型中的短名称，避免列表和值文本过长。
  String get settingsLabel {
    switch (this) {
      case ThemeModeType.light:
        return '浅色';
      case ThemeModeType.dark:
        return '深色';
      case ThemeModeType.system:
        return '自动';
    }
  }
}
