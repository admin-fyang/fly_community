/// 应用根组件文件。
///
/// 装配 GetMaterialApp:标题、双主题(浅/深/跟随系统)、路由表与页面过渡动画。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/theme_controller.dart';
import '../core/theme/theme_transition_layer.dart';
import '../routes/app_pages.dart';
import 'app_config.dart';
import '../core/theme/app_theme.dart';

/// 应用根组件
class App extends StatelessWidget {
  const App({super.key, this.initialRoute});

  /// 可覆盖首屏路由(测试用,默认走 [AppPages.initial] 即登录页)
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: AppConfig.showDebugBanner,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // 双主题 + 跟随系统，由 ThemeController 驱动切换
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: Get.find<ThemeController>().themeMode,
      initialRoute: initialRoute ?? AppPages.initial,
      getPages: AppPages.routes,
      defaultTransition: Transition.cupertino,
      // 保留现有主题切换层；社区版不装配通话浮层。
      builder: (context, child) => ThemeTransitionLayer(
        controller: Get.find<ThemeController>(),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
