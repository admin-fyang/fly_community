/// 聊天设置页。
///
/// 文本大小滑块（即时预览）+ 聊天背景选择 + 聊天列表开关。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/local/app_settings_storage.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_switch.dart';
import '../../shared/widgets/chat/chat_background.dart';
import '../../shared/widgets/section_card.dart';
import 'chat_settings_controller.dart';
import 'widgets/settings_scaffold.dart';
import 'widgets/settings_tile.dart';

/// 聊天设置：文本大小 + 聊天背景 + 聊天列表开关。
class ChatSettingsPage extends GetView<ChatSettingsController> {
  const ChatSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SettingsScaffold(
        title: '聊天设置',
        children: [
          const SettingsSectionHeader('文本大小'),
          SectionCard(children: [_textSizeSection(context)]),
          const SettingsSectionHeader('聊天背景'),
          _backgroundGrid(context),
          const SettingsSectionHeader('聊天列表'),
          SectionCard(
            children: [
              SettingsTile(
                icon: Icons.account_circle,
                iconColor: context.colorScheme.onSurfaceVariant,
                title: '显示头像',
                trailing: AppSwitch(
                  value: controller.showAvatar.value,
                  onChanged: controller.setShowAvatar,
                ),
              ),
              SettingsTile(
                icon: Icons.reorder,
                iconColor: context.colorScheme.onSurfaceVariant,
                title: '两行预览',
                subtitle: '在聊天列表中显示两条消息预览',
                trailing: AppSwitch(
                  value: controller.twoLinePreview.value,
                  onChanged: controller.setTwoLinePreview,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textSizeSection(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSizes.paddingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '文本大小',
                style: AppTextStyles.listPrimary.copyWith(
                  color: colors.onSurface,
                ),
              ),
              Text(
                controller.textSize.value.round().toString(),
                style: AppTextStyles.metadata.copyWith(
                  color: context.tokens.brand,
                ),
              ),
            ],
          ),
          Slider(
            value: controller.textSize.value,
            min: 12,
            max: 30,
            activeColor: context.tokens.brand,
            onChanged: controller.previewTextSize,
            onChangeEnd: controller.saveTextSize,
          ),
          const SizedBox(height: AppSizes.paddingSm),
          // 即时预览气泡与聊天正文读取同一个响应式字号。
          Container(
            padding: const EdgeInsets.all(AppSizes.paddingMd),
            decoration: BoxDecoration(
              color: context.tokens.bubbleOther,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppSizes.radiusBubble),
                topRight: Radius.circular(AppSizes.radiusBubble),
                bottomRight: Radius.circular(AppSizes.radiusBubble),
                bottomLeft: Radius.circular(AppSizes.radiusBubbleTail),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '拖动滑块可以改变气泡中的字体大小，即时预览效果。',
                  style: TextStyle(
                    color: context.tokens.onBubbleOther,
                    fontSize: controller.textSize.value,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '10:45',
                  style: AppTextStyles.badgeLabel.copyWith(
                    color: context.tokens.onBubbleOther.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backgroundGrid(BuildContext context) {
    final colors = context.colorScheme;
    final backgrounds = ChatBackgroundType.values;
    return Row(
      children: [
        for (final background in backgrounds) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => controller.selectBackground(background),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ChatBackground(background: background),
                      if (controller.background.value == background)
                        Positioned(
                          right: AppSizes.paddingSm,
                          bottom: AppSizes.paddingSm,
                          child: Icon(
                            key: ValueKey(
                              'chat-background-selected-${background.name}',
                            ),
                            Icons.check_circle,
                            color: context.tokens.brand,
                            size: 24,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.paddingMd),
        ],
        Expanded(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
              onTap: () => AppToast.info('当前版本仅支持两款内置聊天背景'),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
                  border: Border.all(color: colors.outline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: colors.onSurfaceVariant,
                      size: 28,
                    ),
                    const SizedBox(height: AppSizes.paddingSm),
                    Text(
                      '从相册选择',
                      style: AppTextStyles.badgeLabel.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
