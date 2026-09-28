/// 会话列表页(首页)。
///
/// 顶栏(抽屉+搜索)+ 会话列表,是登录后的主界面。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../main_navigation/main_navigation_insets.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../routes/app_routes.dart';
import '../../data/services/system_time_service.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../../shared/widgets/skeleton/app_skeleton.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_glass_capsule.dart';
import '../../shared/widgets/interaction/app_pressable.dart';
import '../../shared/widgets/empty/app_empty_state.dart';
import '../notifications/notification_unread_controller.dart';
import '../settings/chat_settings_controller.dart';
import 'conversations_controller.dart';
import 'widgets/conversation_item.dart';

/// 会话列表页
class ConversationsPage extends GetView<ConversationsController> {
  const ConversationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 系统配置切换时区后，会话时间无需重新请求数据即可重新渲染。
      Get.find<SystemTimeService>().revision.value;
      // 必须在 Obx 回调的同步构建阶段读取这些 Rx 状态。
      // Builder.builder 会延后到子 Element 构建时才执行，已经脱离
      // 当前 Obx 的依赖收集，导致 Web 首屏数据已完成仍保留骨架屏。
      final conversations = controller.conversations;
      final isInitialLoading = controller.isLoading.value;
      final selectedIds = controller.selectedIds.toSet();
      final selectionMode = controller.isSelectionMode.value;
      final previewMaxLines =
          Get.find<ChatSettingsController>().twoLinePreview.value ? 2 : 1;
      final Widget listBody;
      if (conversations.isEmpty && isInitialLoading) {
        listBody = const _ConversationSkeletonList();
      } else if (conversations.isEmpty) {
        listBody = _empty(context);
      } else {
        listBody = ColoredBox(
          color: context.conversationTokens.background,
          child: ListView.builder(
            padding: EdgeInsets.only(
              top: appTopBarInset(context),
              bottom: MainNavigationInsets.bottomOf(context),
            ),
            controller: controller.scrollController,
            itemCount: conversations.length,
            itemBuilder: (_, index) {
              final conversation = conversations[index];
              return ConversationItem(
                conversation: conversation,
                previewMaxLines: previewMaxLines,
                selected: selectedIds.contains(conversation.id),
                showDivider: false,
                onLongPress: () => controller.enterSelection(conversation),
                onTap: selectionMode
                    ? () => controller.toggleSelection(conversation)
                    : () => Get.toNamed(
                        AppRoutes.chatFor(conversation.id),
                        arguments: conversation,
                      ),
              );
            },
          ),
        );
      }
      return Obx(() {
        final selecting = controller.isSelectionMode.value;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && selecting) controller.exitSelection();
          },
          child: AppPageScaffold(
            extendBodyBehindAppBar: true,
            readActivity: controller.pageReads,
            appBar: selecting
                ? AppSearchAppBar(
                    title: '已选择 ${controller.selectedCount} 项',
                    leadingIcon: Icons.close,
                    onBack: controller.isBatchOperating.value
                        ? null
                        : controller.exitSelection,
                  )
                : AppSearchAppBar(
                    title: controller.homeTitle,
                    mode: controller.topBarMode,
                    showLeading: false,

                    iconSize: 22,
                    foregroundColor: context.semanticColors.textPrimary,

                    onOpenSearch: controller.openSearch,
                    onCloseSearch: controller.closeSearch,
                    onChanged: controller.updateKeyword,
                    actions: const [_NotificationButton()],
                    actionsBeforeSearch: true,
                  ),
            body: listBody,
            floatingActionButtonLocation: const _SelectionCapsuleLocation(),
            floatingActionButton: AnimatedSwitcher(
              duration: AppConstants.animNormal,
              reverseDuration: AppConstants.animFast,
              switchInCurve: AppConstants.motionStandard,
              switchOutCurve: AppConstants.motionExit,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0, 1.25),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: selecting
                  ? KeyedSubtree(
                      key: const ValueKey('conversation-selection-actions'),
                      child: _selectionActions(context),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('conversation-selection-actions-hidden'),
                    ),
            ),
          ),
        );
      });
    });
  }

  Widget _selectionActions(BuildContext context) {
    final busy = controller.isBatchOperating.value;
    return SizedBox(
      width:
          MediaQuery.sizeOf(context).width -
          AppGlassCapsule.horizontalMargin * 2,
      child: AppGlassCapsule(
        child: Row(
          children: [
            _selectionAction(
              context,
              icon: controller.allSelectedMuted
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              label: controller.allSelectedMuted ? '取消静音' : '静音',
              loading: controller.batchAction.value == 'mute',
              onTap: busy || controller.selectedCount == 0
                  ? null
                  : controller.toggleSelectedMuted,
            ),
            _selectionAction(
              context,
              icon: controller.allSelectedPinned
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              label: controller.allSelectedPinned ? '取消置顶' : '置顶',
              loading: controller.batchAction.value == 'pin',
              onTap: busy || controller.selectedCount == 0
                  ? null
                  : controller.toggleSelectedPinned,
            ),
            _selectionAction(
              context,
              icon: Icons.delete_sweep_outlined,
              label: '清空',
              loading: controller.batchAction.value == 'clear',
              onTap: busy || controller.selectedCount == 0
                  ? null
                  : _confirmClear,
            ),
            _selectionAction(
              context,
              icon: Icons.delete_outline,
              label: '删除',
              loading: controller.batchAction.value == 'delete',
              onTap: busy || controller.selectedCount == 0
                  ? null
                  : _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final semantic = context.semanticColors;
    final color = onTap == null
        ? semantic.textTertiary
        : semantic.textSecondary;
    return Expanded(
      child: AppPressable(
        semanticLabel: label,
        onTap: onTap,
        pressedColor: semantic.surfacePressed,
        borderRadius: BorderRadius.circular(AppGlassCapsule.itemRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: AppSizes.bottomNavigationIconSize,
              child: loading
                  ? AppLoadingIndicator(size: 20, color: color)
                  : Icon(
                      icon,
                      size: AppSizes.bottomNavigationIconSize,
                      color: color,
                    ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.badgeLabel.copyWith(color: color)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final count = controller.selectedCount;
    final confirmed = await AppConfirmDialog.show(
      title: '清空聊天记录',
      message: '确定清空已选择的 $count 个会话吗？会话会保留，但现有聊天记录不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (confirmed == true) await controller.clearSelected();
  }

  Future<void> _confirmDelete() async {
    final count = controller.selectedCount;
    final confirmed = await AppConfirmDialog.show(
      title: '删除会话',
      message: '确定删除已选择的 $count 个会话吗？删除前的聊天记录不会恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed == true) await controller.deleteSelected();
  }

  Widget _empty(BuildContext context) {
    final searching = controller.keyword.value.trim().isNotEmpty;
    return ColoredBox(
      color: context.conversationTokens.background,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MainNavigationInsets.bottomOf(context),
        ),
        child: Center(
          child: searching
              ? const AppEmptyState(message: '未找到匹配的会话')
              : const AppEmptyState(
                  message: '没有会话',
                  assetPath: 'assets/icons/empty_state_chat.svg',
                  tintImage: false,
                  imageSize: 160,
                ),
        ),
      ),
    );
  }
}

/// 会话根页保留原“消息通知”能力，不把高时效提醒藏到“我的”中。
class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = Get.find<NotificationUnreadController>().count.value;
      return IconButton(
        tooltip: '消息通知',
        onPressed: () => Get.toNamed(AppRoutes.notifications),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded),
            if (unread > 0)
              PositionedDirectional(
                top: -5,
                end: -7,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: context.conversationTokens.badge,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    border: Border.all(
                      color: context.semanticColors.backgroundPrimary,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: AppTextStyles.badgeLabel.copyWith(
                      color: context.conversationTokens.badgeText,
                      fontSize: 9,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// 首页首次加载骨架列表。
///
/// 仅在本地没有可展示的历史会话时出现；已有缓存时继续展示真实列表，
/// 后台 HTTP 刷新不会用骨架屏覆盖用户已经看到的内容。
class _ConversationSkeletonList extends StatelessWidget {
  const _ConversationSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.conversationTokens.background,
      child: AppSkeletonScope(
        child: ListView.builder(
          padding: (EdgeInsets.only(
            bottom: MainNavigationInsets.bottomOf(context),
          )).add(EdgeInsets.only(top: appTopBarInset(context))),
          itemCount: 8,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (_, __) => const _ConversationSkeletonItem(),
        ),
      ),
    );
  }
}

/// 单条会话骨架，尺寸与现有会话项保持一致，不改变正式列表布局。
class _ConversationSkeletonItem extends StatelessWidget {
  const _ConversationSkeletonItem();

  @override
  Widget build(BuildContext context) {
    final avatarSize = context.conversationTokens.avatarSize;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingItem,
      ),
      child: Row(
        children: [
          AppSkeletonBlock.circle(size: avatarSize),
          const SizedBox(width: AppSizes.paddingItem),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeletonBlock(width: 124, height: 14),
                const SizedBox(height: 8),
                AppSkeletonBlock(
                  width: MediaQuery.sizeOf(context).width * 0.46,
                  height: 10,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.paddingSm),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppSkeletonBlock(width: 42, height: 10),
              SizedBox(height: 10),
              AppSkeletonBlock.circle(size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

/// 复用 Scaffold 的键盘与安全区计算，将默认 16px 浮动间距调整为
/// 与导航一致的 8px；不重复添加系统安全区，保留原有进出场动画。
class _SelectionCapsuleLocation extends FloatingActionButtonLocation {
  const _SelectionCapsuleLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final offset = FloatingActionButtonLocation.centerFloat.getOffset(
      scaffoldGeometry,
    );
    return offset.translate(
      0,
      kFloatingActionButtonMargin - AppGlassCapsule.bottomGap,
    );
  }
}
