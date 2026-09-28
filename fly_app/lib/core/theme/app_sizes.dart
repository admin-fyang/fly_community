/// 尺寸 token：圆角、间距、头像、固定高度
///
/// 全部来源于 DESIGN-Light.md / DESIGN-Dark.md 的 spacing 与 rounded 定义，
/// 以及原型实测值。页面与组件禁止散落 magic number，一律引用这里。
class AppSizes {
  AppSizes._();

  // ===== 间距（4px 基准网格）=====
  static const double base = 4; // 基准单位
  static const double paddingXs = 4;
  static const double paddingSm = 8; // gutter-chat：聊天气泡间距
  static const double paddingMd = 10; // 历史通用中间距；存量页面暂不批量改动
  static const double paddingItem = 12; // DESIGN padding-item：高密度列表项内边距
  static const double paddingLg = 16; // padding-screen：屏幕左右边距
  static const double paddingXl = 24;
  static const double sectionGap = 16; // grouped 页面区块间距

  // 同一发送者连续消息 4px，不同发送者 8px（DESIGN 布局规范）
  static const double bubbleGapSame = 2;
  static const double bubbleGapDiff = 8;
  // Telegram Web `.MessageMeta`：正文间隔 0.4375rem，元信息行盒 18px。
  static const double telegramMessageMetaGap = 7;
  static const double telegramMessageMetaHeight = 18;
  // 字体栅格化产生的亚像素误差不能误判为“末行空间不足”。
  static const double telegramMessageLayoutTolerance = 0.5;

  // ===== 圆角 =====
  static const double radiusSm = 4; // rounded.sm
  static const double radiusDefault = 8; // rounded.DEFAULT：输入框
  static const double radiusMd = 12; // rounded.md
  static const double radiusGrouped = 12; // grouped surface：克制圆角，避免卡片感过重
  static const double radiusLg = 16; // rounded.lg
  static const double radiusXl = 24; // rounded.xl
  static const double radiusBubble = 16; // 用户确认：聊天气泡保留圆润弧度
  static const double radiusBubbleTail = 4; // 气泡指向角（更小圆角）
  static const double radiusFull = 9999; // 胶囊/圆形

  // ===== 头像 =====
  static const double avatarSm = 32; // avatar-size-sm
  static const double avatarMd = 48; // avatar-size-md：会话项/联系人项
  static const double avatarLg = 60; // avatar-size-lg
  static const double avatarConversation = 48; // Light DESIGN：会话列表头像
  static const double avatarConversationDark =
      48; // Deprecated: Light/Dark 使用统一会话几何
  static const double avatarProfile = 100; // 资料页大头像
  static const double avatarEditProfile = 112; // 编辑资料页头像（新版原型 w-28）

  // ===== 固定高度 =====
  /// 顶部导航栏内容区高度，不包含由系统安全区提供的状态栏高度。
  ///
  /// 48dp 同时是 Material 图标按钮的标准最小命中高度，可完整容纳
  /// 聊天页 40dp 头像与 40dp 双行标题，避免高 density 窄屏设备显得臃肿。
  static const double appBarHeight = 48;
  static const double bottomNavigationContentHeight = 56;
  static const double bottomNavigationIconSize = 22;
  static const double conversationItemHeight = 72; // Light：48 + 12 * 2
  static const double conversationItemHeightDark =
      72; // Deprecated: Light/Dark 使用统一会话几何
  static const double incomingCallItemHeight = 88;
  static const double incomingCallMiniHeight = 48;
  static const double incomingCallDragResistanceLimit = 22;
  static const double iconButton = 40; // 圆形图标按钮命中区域
  static const double iconSm = 18; // 列表辅助图标

  // ===== 非文字消息（紧凑消息流）=====
  /// 图片及文件卡片的屏幕最大宽度比例。
  static const double nonTextMessageMaxWidthFactor = 0.65;
  static const double messageCardWidth = 200;
  static const double fileMessageWidth = 184;
  static const double mediaMaxHeight = 236;
  static const double locationMapHeight = 92;
  static const double messageCardAvatar = 40;
  static const double messageCardIconBox = 32;
  static const double liveCardWidth = 188;
  static const double liveCardCoverHeight = 106;
  static const double voiceMessageMinWidth = 136;
  static const double voiceMessageWidthRange = 48;

  // ===== 描边 =====
  static const double hairline = 1; // 兼容旧组件；新分隔线优先使用 1 physical pixel
  static const double settingsTextInset = 58; // 16 + 30 + 12，分割线对齐标题轴
}
