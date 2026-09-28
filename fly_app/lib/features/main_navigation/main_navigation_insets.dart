/// 主导航外壳专用的底部遮挡信息；独立路由不会继承这份布局数据。
library;

import 'package:flutter/widgets.dart';

import '../../shared/widgets/app_glass_capsule.dart';

/// 只传递布局尺寸，不承担业务状态管理。
///
/// [bottom] 包含导航高度、底部间距和系统安全区。页面把它用于滚动末尾
/// 留白及悬浮控件定位，不给整个页面加 Padding，保证内容能经过玻璃后方。
class MainNavigationInsets extends InheritedWidget {
  const MainNavigationInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  /// 胶囊固定高度、水平边距与距安全区的间距，统一供外壳和导航组件使用。
  static const height = AppGlassCapsule.height;
  static const horizontal = AppGlassCapsule.horizontalMargin;
  static const gap = AppGlassCapsule.bottomGap;

  final double bottom;

  /// 不在主外壳内时返回零，不影响独立页面原有布局。
  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MainNavigationInsets>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(MainNavigationInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
