/// 字体层级 token 定义。
///
/// 只定义字号/行高/字重,不写死颜色(颜色由 TextTheme 注入),组件按需 copyWith。
library;

import 'package:flutter/material.dart';

/// 字体层级 token
///
/// 来源 DESIGN 的 typography 段。只定义字号/行高/字重，不写死颜色——
/// 颜色由 ThemeData 的 TextTheme 注入，组件按需 copyWith。
///
/// 字体族统一使用应用内置的 HarmonyOS Sans SC。
///
/// 为什么内置：不同 Android 厂商的中文系统字体在字面大小、字宽和基线方面
/// 存在差异；使用同一字体资源可消除这部分不可控的系统 fallback 差异。
class AppTextStyles {
  AppTextStyles._();

  /// 与 `pubspec.yaml` 中注册名称一致的全局字体族。
  static const String fontFamily = 'HarmonyOSSansSC';

  /// 普通页面标题 18/24/500。
  ///
  /// 页面标题只承担定位作用，不与按钮、角标等需要强调的文字竞争。
  static const TextStyle pageTitle = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w500,
  );

  /// 移动端普通页面标题 17/22/500。
  static const TextStyle pageTitleMobile = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w500,
  );

  /// 首页大标题 20/24/500。
  static const TextStyle homeTitle = TextStyle(
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w500,
  );

  /// 列表主文字 / 昵称 16/22/500。
  static const TextStyle listPrimary = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    // fontWeight: FontWeight.w500,
  );

  /// 按钮文字 16/22/600。
  ///
  /// 与普通列表文字分离，避免为保持操作强调而连带加粗所有列表项。
  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
  );

  /// 导航标题 18/24/500。
  static const TextStyle navTitle = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w500,
  );

  /// 移动端导航标题 17/22/500。
  static const TextStyle navTitleMobile = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w500,
  );

  /// Dark 首页 HTML 顶栏标题：20px / 24px / 600。
  static const TextStyle homeTitleDark = TextStyle(
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w600,
  );

  /// 列表标题 / 昵称 16/22/600
  static const TextStyle listTitle = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    // fontWeight: FontWeight.w600,
  );

  /// 正文 / 气泡 15/20/400
  static const TextStyle messageBody = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w400,
  );

  /// 元信息：时间 / 预览 / 成员数 13/18/400
  static const TextStyle metadata = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  /// Settings subtitle: slightly larger than metadata while remaining quiet.
  static const TextStyle settingsSubtitle = TextStyle(
    fontSize: 14,
    height: 19 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Conversation timestamp: compact so it never competes with the title.
  static const TextStyle conversationTime = TextStyle(
    fontSize: 12.5,
    height: 16 / 12.5,
    fontWeight: FontWeight.w400,
  );

  /// 紧凑强调信息：直播人数、轻量状态数字等 14/18/600。
  static const TextStyle compactEmphasis = TextStyle(
    fontSize: 12,
    height: 18 / 14,
    // fontWeight: FontWeight.w600,
  );

  /// 角标 11/14/600
  static const TextStyle badgeLabel = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
  );

  /// Telegram Web 消息时间：12px 字号、18px 元信息行盒。
  static const TextStyle telegramMessageMeta = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Dark 首页 HTML 会话标题：17px / 22px / 500。
  ///
  /// 仅用于 Dark 会话基准页；Light 继续使用 DESIGN 的 [listTitle]。
  static const TextStyle conversationTitleDark = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w500,
  );

  /// Dark 首页 HTML 会话预览：15px / 20px / 400。
  static const TextStyle conversationPreviewDark = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w400,
  );

  /// Dark 首页 HTML 时间：12px / 16px / 400。
  static const TextStyle conversationTimeDark = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Dark 首页 HTML 未读角标：12px / 16px / 700。
  static const TextStyle conversationBadgeDark = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
  );

  /// Dark 首页侧边栏问候语：20px / 26px / 700。
  static const TextStyle drawerGreetingDark = TextStyle(
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
  );

  /// Dark 首页侧边栏用户名：20px / 26px / 500。
  static const TextStyle drawerNameDark = TextStyle(
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w500,
  );

  /// Dark 首页侧边栏 FID：12px / 16px / 400。
  static const TextStyle drawerIdDark = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
  );

  /// 构建 TextTheme：将 token 映射到 Material 语义槽位，并注入主题文字色
  static TextTheme buildTextTheme({
    required Color onSurface,
    required Color onSurfaceVariant,
  }) {
    return TextTheme(
      titleLarge: navTitle.copyWith(color: onSurface),
      titleMedium: navTitleMobile.copyWith(color: onSurface),
      titleSmall: listTitle.copyWith(color: onSurface),
      bodyLarge: messageBody.copyWith(color: onSurface),
      bodyMedium: messageBody.copyWith(color: onSurface),
      bodySmall: metadata.copyWith(color: onSurfaceVariant),
      labelSmall: badgeLabel.copyWith(color: onSurface),
    );
  }
}
