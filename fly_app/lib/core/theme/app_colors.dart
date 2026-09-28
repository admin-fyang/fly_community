/// 颜色 token 定义。
///
/// 集中管理浅色 / 深色两套色板,并通过 [AppColorTokens] 主题扩展
/// 暴露 IM 专有语义色(气泡、在线、危险、分割线等)。
library;

import 'package:flutter/material.dart';

/// 颜色 token
///
/// 取值来源（优先级）：DESIGN-Light.md / DESIGN-Dark.md 的 colors 段，
/// 并参考原型实际渲染（聊天/资料页深色采用 Telegram 经典 #17212B 体系）。
///
/// - 常规语义色（primary / surface / onSurface 等）通过 [ColorScheme] 暴露，
///   组件用 `context.colorScheme` 访问。
/// - IM 专有语义色（气泡、未读角标、在线状态等）通过 [AppColorTokens] 暴露，
///   组件用 `context.tokens` 访问，随主题自动切换。
///
/// 品牌强调色 #24a1de（primary-container）两套主题一致，只用于发送按钮、
/// 未读角标、激活态、关键 CTA。其余大面积一律中性色。
class AppColors {
  AppColors._();

  /// 品牌强调色：两主题通用，仅用于关键交互点
  static const Color brand = Color(0xFF24A1DE);

  // ===================== 浅色 =====================

  /// 浅色主题主色，用于 Material 主色语义及强调型控件。
  static const Color lightPrimary = Color(0xFF24A1DE);

  /// 浅色主题主色背景上的前景色，用于主色按钮文字和图标。
  static const Color lightOnPrimary = Color(0xFFFFFFFF);

  /// 浅色页面基础底色。
  ///
  /// 采用冷灰蓝分层，与纯白抬升表面形成克制但可感知的层级。
  static const Color lightBackground = Color(0xFFFFFFFF);

  /// 浅色抬升表面色，用于顶栏、卡片和底部输入区。
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// 浅色低位容器色，用于分组区块和弱强调区域。
  ///
  /// 新版资料编辑原型明确指定该颜色，资料区块需保持一致。
  static const Color lightSurfaceContainerLow = Color(0xFFF8FAFB);

  /// 浅色普通容器色，用于输入框和次级内容容器。
  static const Color lightSurfaceContainer = Color(0xFFF2F5F7);

  /// 浅色较高层容器色，用于图标底板和较明显的分层区域。
  static const Color lightSurfaceContainerHigh = Color(0xFFEDF1F4);

  /// 浅色最高层容器色，用于禁用态、弱角标及需要更强边界的区域。
  static const Color lightSurfaceContainerHighest = Color(0xFFE6EBEF);

  /// 浅色柔和品牌背景，用于钱包概览等低饱和重点区域。
  static const Color lightBrandSoft = Color(0xFFE8F4FA);

  /// 浅色柔和品牌背景上的文字和图标颜色。
  static const Color lightOnBrandSoft = Color(0xFF174B63);

  /// 浅色极细分割线颜色，用于列表和抬升表面的轻量边界。
  static const Color lightDivider = Color(0xFFE7ECF0);

  /// 浅色表面上的主文字颜色。
  static const Color lightOnSurface = Color(0xFF17212B);

  /// 浅色表面上的次要文字和辅助图标颜色。
  // static const Color lightOnSurfaceVariant = Color(0xFF3E4850);
  static const Color lightOnSurfaceVariant = Color(0xFF708499);

  /// 浅色轮廓颜色，用于输入边界和需要清晰识别的描边。
  static const Color lightOutline = Color(0xFF93A2AF);

  /// 浅色弱轮廓颜色，用于比普通分割线更明显的次级描边。
  static const Color lightOutlineVariant = Color(0xFFD5DEE5);

  /// 浅色错误状态颜色，用于校验失败和危险反馈。
  static const Color lightError = Color(0xFFBA1A1A);

  /// 浅色错误背景上的文字和图标颜色。
  static const Color lightOnError = Color(0xFFFFFFFF);

  // 浅色 IM 专有

  /// 浅色聊天消息流背景，与白色接收气泡形成层级。
  static const Color lightChatBackground = Color(0xFFDCE7EB);

  /// 浅色自己发送消息的气泡背景。
  static const Color lightBubbleSelf = Color(0xFF24A1DE);

  /// 浅色自己发送消息气泡上的文字和状态图标颜色。
  static const Color lightOnBubbleSelf = Color(0xFFFFFFFF);

  /// 浅色对方发送消息的气泡背景。
  static const Color lightBubbleOther = Color(0xFFFFFFFF);

  /// 浅色对方发送消息气泡上的文字颜色。
  static const Color lightOnBubbleOther = Color(0xFF17212B);

  /// 浅色列表项按下、选中和短暂交互反馈背景。
  static const Color lightItemActive = Color(0xFFEEF4F7);

  // ===================== 深色 =====================

  /// 深色主题主色，用于关键操作和激活状态。
  static const Color darkPrimary = Color(0xFF74C7F2);

  /// 深色主题主色背景上的前景色。
  static const Color darkOnPrimary = Color(0xFFFFFFFF);

  /// Dark 首页 HTML 主列表背景（surface）。
  static const Color darkHomeBackground = Color(0xFF05080D);

  /// 蓝黑预览版：保留 Telegram Night 的导航层级，仅将中性黑轻微冷蓝化。
  static const Color darkHomeAppBar = Color(0xE6111820);

  /// Dark 首页 HTML 顶栏分割线（surface-container-highest）。
  static const Color darkHomeAppBarDivider = Color(0x8C344353);

  /// 蓝黑预览版会话列表分割线：保持 Telegram 的低对比层级，改为冷蓝灰。
  static const Color darkHomeListDivider = Color(0x8C344353);

  /// Dark 首页 HTML 主文字（on-surface）。
  static const Color darkHomeOnSurface = Color(0xFFF7F9FC);

  /// Dark 首页 HTML 次级文字（on-surface-variant）。
  static const Color darkHomeOnSurfaceVariant = Color(0xFF8795A4);

  /// Dark 首页 HTML 功能强调色（primary）。
  ///
  /// 与品牌标使用的 #24A1DE 分离：列表中的时间、媒体类型等功能状态
  /// 使用更柔和的浅蓝，避免深色背景上出现廉价的高饱和荧光感。
  static const Color darkHomePrimary = Color(0xFF61BCF9);

  /// Dark 首页 HTML 侧边栏背景。
  static const Color darkDrawerSurface = Color(0xFF111820);

  /// Dark 首页 HTML 侧边栏分割线。
  static const Color darkDrawerDivider = Color(0x8C344353);

  /// Dark 首页 HTML 侧边栏按压/悬停背景。
  static const Color darkDrawerActive = Color(0xFF283442);

  /// Dark 首页 HTML 侧边栏主文字。
  static const Color darkDrawerText = Color(0xFFF7F9FC);

  /// Dark 首页 HTML 侧边栏次要文字和图标。
  static const Color darkDrawerMuted = Color(0xFF98A5B3);

  /// Dark 首页 HTML 用户名强调色。
  static const Color darkDrawerNameAccent = Color(0xFFC084FC);

  /// 蓝黑预览版页面基础底色；明度层级参考 Telegram Night，色相为产品定制。
  static const Color darkBackground = Color(0xFF05080D);

  /// 蓝黑预览版普通内容表面；保持 Telegram Night 的 surface 层级关系。
  static const Color darkSurface = Color(0xFF111820);

  /// 深色低位容器色，用于 grouped canvas 与弱嵌套区域。
  static const Color darkSurfaceContainerLow = Color(0xFF0B1017);

  /// 深色普通容器色，用于输入框、卡片和次级内容容器。
  static const Color darkSurfaceContainer = Color(0xFF111820);

  /// 深色较高层容器色，用于浮层、菜单和突出内容。
  static const Color darkSurfaceContainerHigh = Color(0xFF1A232D);

  /// 深色最高层容器色，用于按压态、禁用态及需要更强边界的区域。
  static const Color darkSurfaceContainerHighest = Color(0xFF202A35);

  /// 深色表面上的主文字颜色。
  static const Color darkOnSurface = Color(0xFFF7F9FC);

  /// 深色表面上的次要文字和辅助图标颜色。
  static const Color darkOnSurfaceVariant = Color(0xFF98A5B3);

  /// 深色轮廓颜色，用于需要清晰识别的描边。
  static const Color darkOutline = Color(0xFF7F8D9A);

  /// 深色弱轮廓颜色，用于极细分割线和低对比边界。
  static const Color darkOutlineVariant = Color(0x8C344353);

  /// 深色错误状态颜色，用于校验失败和危险反馈。
  static const Color darkError = Color(0xFFEB5545);

  /// 深色错误背景上的文字和图标颜色。
  static const Color darkOnError = Color(0xFFFFFFFF);

  // 深色 IM 专有

  /// 深色聊天消息流背景，低于普通页面表面层级。
  static const Color darkChatBackground = Color(0xFF071018);

  /// 深色自己发送消息的气泡背景，使用低刺激蓝灰色。
  static const Color darkBubbleSelf = Color(0xFF2AABEE);

  /// 深色自己发送消息气泡上的文字和状态图标颜色。
  static const Color darkOnBubbleSelf = Color(0xFFFFFFFF);

  /// 深色对方发送消息的气泡背景。
  static const Color darkBubbleOther = Color(0xE6121A22);

  /// 深色对方发送消息气泡上的文字颜色。
  static const Color darkOnBubbleOther = Color(0xFFFFFFFF);

  /// 深色列表项按下、选中和短暂交互反馈背景。
  static const Color darkItemActive = Color(0xFF283442);

  // ===================== 反馈色（两主题）=====================

  /// 浅色成功和在线状态颜色。
  static const Color successLight = Color(0xFF45D26F);

  /// 深色成功和在线状态颜色。
  static const Color successDark = Color(0xFF45D26F);

  /// 浅色危险操作颜色，用于删除、退出和解散等操作。
  // static const Color dangerLight = Color(0xFFBA1A1A);
  static const Color dangerLight = Color(0xFFEF595A);

  /// 深色危险操作颜色，用于删除、退出和解散等操作。
  static const Color dangerDark = Color(0xFFEB5545);

  /// 浅色静音会话未读角标背景。
  static const Color unreadMutedLight = Color(0xFFDFE3E8);

  /// 浅色静音会话未读角标文字颜色。
  static const Color onUnreadMutedLight = Color(0xFF3E4850);

  /// 深色静音会话未读角标背景。
  static const Color unreadMutedDark = Color(0xFF666666);

  /// 深色静音会话未读角标文字颜色。
  static const Color onUnreadMutedDark = Color(0xFF000000);
}

/// IM 专有语义色，挂载到 ThemeData 的 extension，随主题自动切换。
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.brand,
    required this.chatBackground,
    required this.bubbleSelf,
    required this.onBubbleSelf,
    required this.bubbleOther,
    required this.onBubbleOther,
    required this.unreadActive,
    required this.onUnreadActive,
    required this.unreadMuted,
    required this.onUnreadMuted,
    required this.online,
    required this.danger,
    required this.divider,
    required this.itemActive,
  });

  /// 当前主题的品牌强调色，用于发送、激活态和关键 CTA。
  final Color brand;

  /// 当前主题的聊天消息流背景。
  final Color chatBackground;

  /// 当前主题中自己发送消息的气泡背景。
  final Color bubbleSelf;

  /// 当前主题中自己发送消息气泡上的前景色。
  final Color onBubbleSelf;

  /// 当前主题中对方发送消息的气泡背景。
  final Color bubbleOther;

  /// 当前主题中对方发送消息气泡上的前景色。
  final Color onBubbleOther;

  /// 当前主题的活跃会话未读角标背景。
  final Color unreadActive;

  /// 当前主题的活跃会话未读角标前景色。
  final Color onUnreadActive;

  /// 当前主题的静音会话未读角标背景。
  final Color unreadMuted;

  /// 当前主题的静音会话未读角标前景色。
  final Color onUnreadMuted;

  /// 当前主题的在线和成功状态颜色。
  final Color online;

  /// 当前主题的危险操作和负向反馈颜色。
  final Color danger;

  /// 当前主题的极细分割线颜色。
  final Color divider;

  /// 当前主题的列表项按下和选中反馈背景。
  final Color itemActive;

  /// 浅色主题 IM 专有语义色集合。
  static const AppColorTokens light = AppColorTokens(
    brand: AppColors.brand,
    chatBackground: AppColors.lightChatBackground,
    bubbleSelf: AppColors.lightBubbleSelf,
    onBubbleSelf: AppColors.lightOnBubbleSelf,
    bubbleOther: AppColors.lightBubbleOther,
    onBubbleOther: AppColors.lightOnBubbleOther,
    unreadActive: AppColors.brand,
    onUnreadActive: Color(0xFFFFFFFF),
    unreadMuted: AppColors.unreadMutedLight,
    onUnreadMuted: AppColors.onUnreadMutedLight,
    online: AppColors.successLight,
    danger: AppColors.dangerLight,
    divider: AppColors.lightDivider,
    itemActive: AppColors.lightItemActive,
  );

  /// 深色主题 IM 专有语义色集合。
  static const AppColorTokens dark = AppColorTokens(
    brand: AppColors.brand,
    chatBackground: AppColors.darkChatBackground,
    bubbleSelf: AppColors.darkBubbleSelf,
    onBubbleSelf: AppColors.darkOnBubbleSelf,
    bubbleOther: AppColors.darkBubbleOther,
    onBubbleOther: AppColors.darkOnBubbleOther,
    unreadActive: Color(0xFFFFFFFF),
    onUnreadActive: Color(0xFF000000),
    unreadMuted: AppColors.unreadMutedDark,
    onUnreadMuted: AppColors.onUnreadMutedDark,
    online: AppColors.successDark,
    danger: AppColors.dangerDark,
    divider: AppColors.darkOutlineVariant,
    itemActive: AppColors.darkItemActive,
  );

  @override
  AppColorTokens copyWith({
    Color? brand,
    Color? chatBackground,
    Color? bubbleSelf,
    Color? onBubbleSelf,
    Color? bubbleOther,
    Color? onBubbleOther,
    Color? unreadActive,
    Color? onUnreadActive,
    Color? unreadMuted,
    Color? onUnreadMuted,
    Color? online,
    Color? danger,
    Color? divider,
    Color? itemActive,
  }) {
    return AppColorTokens(
      brand: brand ?? this.brand,
      chatBackground: chatBackground ?? this.chatBackground,
      bubbleSelf: bubbleSelf ?? this.bubbleSelf,
      onBubbleSelf: onBubbleSelf ?? this.onBubbleSelf,
      bubbleOther: bubbleOther ?? this.bubbleOther,
      onBubbleOther: onBubbleOther ?? this.onBubbleOther,
      unreadActive: unreadActive ?? this.unreadActive,
      onUnreadActive: onUnreadActive ?? this.onUnreadActive,
      unreadMuted: unreadMuted ?? this.unreadMuted,
      onUnreadMuted: onUnreadMuted ?? this.onUnreadMuted,
      online: online ?? this.online,
      danger: danger ?? this.danger,
      divider: divider ?? this.divider,
      itemActive: itemActive ?? this.itemActive,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      brand: Color.lerp(brand, other.brand, t)!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      bubbleSelf: Color.lerp(bubbleSelf, other.bubbleSelf, t)!,
      onBubbleSelf: Color.lerp(onBubbleSelf, other.onBubbleSelf, t)!,
      bubbleOther: Color.lerp(bubbleOther, other.bubbleOther, t)!,
      onBubbleOther: Color.lerp(onBubbleOther, other.onBubbleOther, t)!,
      unreadActive: Color.lerp(unreadActive, other.unreadActive, t)!,
      onUnreadActive: Color.lerp(onUnreadActive, other.onUnreadActive, t)!,
      unreadMuted: Color.lerp(unreadMuted, other.unreadMuted, t)!,
      onUnreadMuted: Color.lerp(onUnreadMuted, other.onUnreadMuted, t)!,
      online: Color.lerp(online, other.online, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      itemActive: Color.lerp(itemActive, other.itemActive, t)!,
    );
  }
}
