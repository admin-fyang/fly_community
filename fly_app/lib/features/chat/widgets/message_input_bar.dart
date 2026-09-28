/// 聊天输入栏组件。
///
/// 文本输入 / 按住说话切换,含表情、多功能面板与发送按钮。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/enums/chat_input_mode.dart';
import '../chat_controller.dart';

/// 聊天底部输入栏
///
/// 还原原型切换效果：
/// - 左侧 `+` 按钮在语音模式下做宽度收缩动画消失；
/// - 中间文本层 ↔ 语音层为纵向滑动 + 淡入淡出的双层叠加切换
///   （文本上滑移出，语音从下方滑入）；
/// - 右侧圆形按钮在「麦克风 / 发送 / 键盘」间切换。
class MessageInputBar extends StatelessWidget {
  const MessageInputBar({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final inputTokens = context.chatInputTokens;
    final inputColor = inputTokens.inputBackground;
    return Obx(() {
      final mode = controller.inputMode.value;
      const isVoice = false;
      final keyboardTransitionPending =
          controller.keyboardTransitionPending.value;
      final inputToolOpen =
          mode.isPanelOpen ||
          keyboardTransitionPending ||
          MediaQuery.viewInsetsOf(context).bottom > 0;
      final bottomSafe = MediaQuery.paddingOf(context).bottom;

      final toolbar = AnimatedPadding(
        duration: AppConstants.animNormal,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          6,
          6,
          6,
          inputToolOpen ? 6 : bottomSafe + 6,
        ),
        child: AnimatedBuilder(
          animation: controller.textController,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _measureTextLayout(
                  context,
                  constraints.maxWidth,
                  isVoice,
                );
                return _inputStack(
                  context,
                  colors,
                  mode,
                  isVoice,
                  metrics,
                  inputColor,
                );
              },
            );
          },
        ),
      );

      // 仅保留输入胶囊本身，不再给整块底部工具栏铺设背景。
      return toolbar;
    });
  }

  /// 计算输入栏当前应使用紧凑单行模式还是宽幅多行模式。
  ///
  /// 单行时维持原来的 Telegram 式紧凑工具栏；一旦文字在紧凑区域中需要
  /// 换行，就切换到宽幅多行布局：文字独占上层近乎完整宽度，附件/表情/
  /// 发送按钮进入底部控制层。这样上面的每一行都不会永久为左右按钮让位。
  _InputTextMetrics _measureTextLayout(
    BuildContext context,
    double barWidth,
    bool isVoice,
  ) {
    if (isVoice || controller.textController.text.isEmpty) {
      return const _InputTextMetrics.singleLine();
    }

    // 紧凑模式实际可用宽度：附件 44 + 主按钮 42 + 间距 4 + 表情预留 36。
    // 只用它判断何时从单行工具栏进入多行模式。
    final compactTextWidth = barWidth - 44 - 42 - 4 - 36;
    if (compactTextWidth <= 0) {
      return const _InputTextMetrics.singleLine();
    }

    final compactPainter = TextPainter(
      text: TextSpan(
        text: controller.textController.text,
        style: AppTextStyles.messageBody,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: compactTextWidth);

    if (compactPainter.computeLineMetrics().length <= 1) {
      return const _InputTextMetrics.singleLine();
    }

    // 多行模式文字只保留正常的左右内容边距，按钮不再参与每一行的宽度。
    const horizontalTextInset = 16.0;
    final expandedTextWidth = barWidth - horizontalTextInset * 2;
    final expandedPainter = TextPainter(
      text: TextSpan(
        text: controller.textController.text,
        style: AppTextStyles.messageBody,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 5,
    )..layout(maxWidth: expandedTextWidth);

    final expandedLineCount = expandedPainter.computeLineMetrics().length.clamp(
      1,
      5,
    );
    // 20px 行盒 + 12px 顶部/文本区缓冲 + 42px 底部控制层。
    // 超过 5 行后 TextField 自身滚动，整个输入胶囊不再继续增高。
    final textAreaHeight = expandedLineCount * 20.0 + 12.0;
    final totalHeight = textAreaHeight + 42.0;
    return _InputTextMetrics(
      isMultiline: true,
      fieldHeight: totalHeight.clamp(74.0, 154.0).toDouble(),
    );
  }

  /// 输入栏主体：表情按钮在输入框内部与最右侧操作列之间平滑移动。
  Widget _inputStack(
    BuildContext context,
    ColorScheme colors,
    ChatInputMode mode,
    bool isVoice,
    _InputTextMetrics metrics,
    Color inputColor,
  ) {
    final multiline = metrics.isMultiline;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .18
                  : .10,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        child: AnimatedContainer(
          duration: AppConstants.animNormal,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: inputColor,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(
              color: context.chatInputTokens.inputBorder,
              width: hairline,
            ),
          ),
          child: AnimatedSize(
            duration: AppConstants.animNormal,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: multiline && !isVoice ? metrics.fieldHeight : 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 单行仍使用左右工具按钮夹住文本的紧凑布局；多行后文本
                  // 独占上层近乎完整宽度，底部 42px 单独留给控制按钮。
                  AnimatedPositioned(
                    duration: AppConstants.animNormal,
                    curve: Curves.easeOutCubic,
                    left: isVoice
                        ? 0
                        : multiline
                        ? 16
                        : 44,
                    right: multiline && !isVoice ? 16 : 46,
                    top: 0,
                    bottom: multiline && !isVoice ? 42 : 0,
                    child: _switcher(
                      context,
                      isVoice,
                      multiline && !isVoice,
                      multiline && !isVoice ? metrics.fieldHeight - 42 : 42,
                    ),
                  ),

                  // 多行模式下三个操作按钮成为独立的底部控制层，不再缩窄
                  // 上方每一行文字；单行位置保持与原版完全一致。
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: 44,
                    height: 42,
                    child: _collapsibleAdd(context, colors, mode, isVoice),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: 42,
                    height: 42,
                    child: _RightActionRail(
                      controller: controller,
                      buttonSize: 42,
                      height: 42,
                    ),
                  ),
                  Positioned(
                    right: 46,
                    bottom: 3,
                    width: 36,
                    height: 36,
                    child: IgnorePointer(
                      ignoring: isVoice,
                      child: AnimatedOpacity(
                        duration: AppConstants.animFast,
                        opacity: isVoice ? 0 : 1,
                        child: _EmojiButton(
                          controller: controller,
                          mode: mode,
                          expanded: false,
                          iconSize: 22,
                          expandedIconSize: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 左侧附件按钮：语音模式下宽度收缩并淡出
  Widget _collapsibleAdd(
    BuildContext context,
    ColorScheme colors,
    ChatInputMode mode,
    bool isVoice,
  ) {
    return AnimatedContainer(
      duration: AppConstants.animNormal,
      curve: Curves.easeInOut,
      width: isVoice ? 0 : 44,
      child: ClipRect(
        child: AnimatedOpacity(
          duration: AppConstants.animFast,
          opacity: isVoice ? 0 : 1,
          child: SizedBox(
            width: 44,
            height: 42,
            child: IconButton(
              icon: SvgPicture.asset(
                'assets/icons/chat/attachment.svg',
                width: 21,
                height: 21,
                colorFilter: ColorFilter.mode(
                  context.chatInputTokens.control,
                  BlendMode.srcIn,
                ),
                semanticsLabel: '选择附件',
              ),
              color: context.chatInputTokens.control,
              onPressed: controller.toggleMore,
            ),
          ),
        ),
      ),
    );
  }

  /// 社区版仅保留文本输入层，布局尺寸与原输入栏一致。
  Widget _switcher(
    BuildContext context,
    bool isVoice,
    bool isMultiline,
    double fieldHeight,
  ) => _textField(context, isMultiline, fieldHeight);

  /// 文本输入框。
  ///
  /// 单行时为表情按钮保留右侧空间；多行时按钮已经移到底部控制层，
  /// 因此文字层取消横向按钮占位，让上方内容使用完整可用宽度。
  Widget _textField(
    BuildContext context,
    bool isMultiline,
    double fieldHeight,
  ) {
    return AnimatedContainer(
      duration: AppConstants.animNormal,
      curve: Curves.easeOutCubic,
      height: fieldHeight,
      alignment: Alignment.center,
      child: AnimatedPadding(
        duration: AppConstants.animNormal,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(right: isMultiline ? 0 : 36),
        child: Transform.translate(
          // isCollapsed 模式下 TextField 没有额外垂直空间，
          // TextAlignVertical 无法产生实际偏移。仅移动 Web 单行文字的
          // 绘制层，保证 Hint、光标和输入文字同步校正且不触发布局。
          offset: Offset(0, kIsWeb && !isMultiline ? -5.5 : 0),
          child: TextField(
            controller: controller.textController,
            focusNode: controller.inputFocusNode,
            onTap: controller.onInputFocus,
            cursorColor: context.chatInputTokens.accent,
            cursorHeight: 20,
            style: AppTextStyles.messageBody.copyWith(
              color: context.chatInputTokens.text,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            strutStyle: const StrutStyle(
              fontSize: 15,
              height: 20 / 15,
              forceStrutHeight: true,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            textAlignVertical: TextAlignVertical.center,
            // 文字层保持 20px 固定行盒，由外层在 42px 输入区域内居中；
            // 不使用 expands，避免 InputDecorator 将满高 EditableText
            // 误判为内容本身高度，导致 Web 端基线向下偏移。
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              filled: false,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: '输入消息',
              hintStyle: AppTextStyles.messageBody.copyWith(
                color: context.chatInputTokens.placeholder,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 输入文本的派生布局数据，仅服务于当前 Widget 的展示动画。
class _InputTextMetrics {
  const _InputTextMetrics({
    required this.isMultiline,
    required this.fieldHeight,
  });

  const _InputTextMetrics.singleLine() : isMultiline = false, fieldHeight = 42;

  final bool isMultiline;
  final double fieldHeight;
}

/// 表情/键盘按钮。
///
/// 单行与多行共用同一个实例，移动时不会产生两个图标交叠或点击区冲突。
class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.controller,
    required this.mode,
    required this.expanded,
    required this.iconSize,
    required this.expandedIconSize,
  });

  final ChatController controller;
  final ChatInputMode mode;
  final bool expanded;
  final double iconSize;
  final double expandedIconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: mode == ChatInputMode.emoji
            ? controller.showKeyboard
            : controller.toggleEmoji,
        child: TweenAnimationBuilder<double>(
          duration: AppConstants.animNormal,
          curve: Curves.easeOutCubic,
          tween: Tween<double>(end: expanded ? expandedIconSize : iconSize),
          builder: (context, iconSize, _) => Center(
            child: mode == ChatInputMode.emoji
                ? SvgPicture.asset(
                    'assets/icons/chat/keyboard.svg',
                    width: iconSize,
                    height: iconSize,
                    colorFilter: ColorFilter.mode(
                      context.chatInputTokens.control,
                      BlendMode.srcIn,
                    ),
                    semanticsLabel: '键盘',
                  )
                : SvgPicture.asset(
                    'assets/icons/chat/emoji.svg',
                    width: iconSize,
                    height: iconSize,
                    colorFilter: ColorFilter.mode(
                      context.chatInputTokens.control,
                      BlendMode.srcIn,
                    ),
                    semanticsLabel: '表情',
                  ),
          ),
        ),
      ),
    );
  }
}

/// 最右侧操作按钮占位。
///
/// 单行与多行都保持 42px 底部控制高度；多行的额外高度只属于文字区域。
class _RightActionRail extends StatelessWidget {
  const _RightActionRail({
    required this.controller,
    required this.buttonSize,
    required this.height,
  });

  final ChatController controller;
  final double buttonSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppConstants.animNormal,
      curve: Curves.easeOutCubic,
      width: buttonSize,
      height: height,
      alignment: Alignment.bottomCenter,
      child: _MainButton(controller: controller, size: buttonSize),
    );
  }
}

/// 右侧主按钮：发送。
class _MainButton extends StatelessWidget {
  const _MainButton({required this.controller, required this.size});

  final ChatController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final composing = controller.isComposing.value;

      late final StatelessWidget? icon;
      VoidCallback? onTap;

      if (composing) {
        icon = SvgPicture.asset(
          'assets/icons/chat/send.svg',
          width: 21,
          height: 21,
          colorFilter: ColorFilter.mode(context.chatInputTokens.accent, BlendMode.srcIn),
          semanticsLabel: '发送',
        );
        onTap = controller.sendText;
      } else {
        // 社区版不提供语音消息，保留原按钮位置并显示禁用的发送图标。
        icon = SvgPicture.asset(
          'assets/icons/chat/send.svg',
          width: 21,
          height: 21,
          colorFilter: ColorFilter.mode(context.chatInputTokens.control, BlendMode.srcIn),
          semanticsLabel: '输入消息后发送',
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          // 保留44px点击区域和布局占位
          dimension: size,
          child: Center(
            child: AnimatedContainer(
              duration: AppConstants.animFast,
              curve: Curves.easeOutCubic,
              width: 32,
              height: 32,
              /*decoration: BoxDecoration(
                color: composing
                    ? context.chatInputTokens.accent
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),*/
              child: icon,
            ),
          ),
        ),
      );
    });
  }
}
