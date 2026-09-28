/// 聊天表情面板组件。
///
/// 输入栏展开的表情选择面板。
library;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../chat_controller.dart';

/// 表情面板。
///
/// 通过 `emoji_picker_flutter` 直接绑定聊天输入框的
/// [ChatController.textController]，选择表情后由同一个输入监听驱动发送按钮状态。
///
/// 这里使用 StatefulWidget 缓存 [Config]：emoji_picker_flutter 会在
/// `oldWidget.config != widget.config` 时异步重新加载分类数据。如果聊天页因为
/// Obx / IME viewInsets 高频重建，而每帧都创建一个新 Config，就可能产生并发
/// `_updateEmojis()`，最终让 9 个分类被重复追加成 17 个，而内部 TabController
/// 仍保持 9，触发 Flutter 的 TabBar 长度断言。
class ChatEmojiPanel extends StatefulWidget {
  const ChatEmojiPanel({
    super.key,
    required this.controller,
    required this.height,
  });

  final ChatController controller;
  final double height;

  @override
  State<ChatEmojiPanel> createState() => _ChatEmojiPanelState();
}

class _ChatEmojiPanelState extends State<ChatEmojiPanel> {
  Config? _pickerConfig;
  String? _configSignature;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final isDark = context.isDark;

    // Telegram-iOS Night inputMediaPanel：保持原有半透明深色层，但只允许外层
    // 绘制一次。EmojiPicker 内部的 emoji/category/search 背景全部透明，避免
    // 黑色主题下同一 alpha 背景重复合成后看起来像上下两层面板。
    const darkPanelBackground = Color.fromRGBO(36, 36, 36, 0.665);
    const darkPanelIcon = Color(0xFF808080);
    final darkPanelHighlightedIcon =
        Color.lerp(darkPanelIcon, Colors.white, 0.35)!;
    const darkPanelSelection = Color(0x1AFFFFFF);
    const darkPanelSeparator = Color(0x8C545458);
    const darkSearchControl = Color(0xFF8D8E93);

    final panelBackground =
        isDark ? darkPanelBackground : colors.surfaceContainerLowest;
    final compact = widget.height < 260;
    final tall = widget.height > 340;
    const topPadding = AppSizes.paddingXs;
    final pickerHeight =
        (widget.height - topPadding).clamp(0.0, widget.height).toDouble();

    // 只有真正影响 EmojiPicker 配置的参数变化时才创建新 Config。
    // 普通 Obx / 键盘帧重建会复用完全相同的 Config 实例，不再触发包内部
    // didUpdateWidget -> _updateEmojis()。
    final signature = <Object>[
      isDark,
      compact,
      tall,
      pickerHeight.round(),
      colors.surfaceContainerLowest.value,
      colors.onSurfaceVariant.value,
      context.tokens.brand.value,
      context.tokens.divider.value,
    ].join(':');

    if (_pickerConfig == null || _configSignature != signature) {
      _configSignature = signature;
      _pickerConfig = Config(
        height: pickerHeight,
        locale: const Locale('zh'),
        emojiViewConfig: EmojiViewConfig(
          columns: tall ? 9 : 8,
          emojiSizeMax: compact ? 26 : (tall ? 30 : 28),
          // 背景只交给最外层 ChatEmojiPanel 绘制，内部保持透明。
          backgroundColor: Colors.transparent,
          gridPadding: EdgeInsets.symmetric(
            horizontal: AppSizes.paddingSm,
            vertical: compact ? 0 : AppSizes.paddingXs,
          ),
          noRecents: const SizedBox.shrink(),
        ),
        categoryViewConfig: CategoryViewConfig(
          tabBarHeight: compact ? 34 : 38,
          backgroundColor: Colors.transparent,
          indicatorColor:
              isDark ? darkPanelSelection : context.tokens.brand,
          iconColor: isDark ? darkPanelIcon : colors.onSurfaceVariant,
          iconColorSelected:
              isDark ? darkPanelHighlightedIcon : context.tokens.brand,
          backspaceColor: isDark ? darkPanelIcon : context.tokens.brand,
          dividerColor:
              isDark ? darkPanelSeparator : context.tokens.divider,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          // 聊天输入栏已经提供删除与面板切换入口，不重复占用操作栏。
          enabled: false,
          backgroundColor: Colors.transparent,
          buttonColor: Colors.transparent,
          buttonIconColor:
              isDark ? darkPanelIcon : context.tokens.brand,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: Colors.transparent,
          buttonIconColor:
              isDark ? darkSearchControl : context.tokens.brand,
        ),
      );
    }

    return Container(
      color: panelBackground,
      height: widget.height,
      padding: const EdgeInsets.only(top: topPadding),
      child: SizedBox(
        height: pickerHeight,
        child: EmojiPicker(
          // 配置确实改变时使用新 State，避免旧实例进行中的异步分类加载与
          // 新配置共享/竞争同一份内部分类列表。
          key: ValueKey(_configSignature),
          textEditingController: widget.controller.textController,
          config: _pickerConfig!,
        ),
      ),
    );
  }
}
