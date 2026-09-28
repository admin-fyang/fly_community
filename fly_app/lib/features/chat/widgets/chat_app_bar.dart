/// 聊天顶栏组件。
///
/// 普通态展示对方信息与操作,多选态切换为批量操作栏。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/search/app_search_app_bar.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../chat_controller.dart';

/// 聊天页顶栏
///
/// 普通态：返回 + 单聊头像/标题 + 副标题 + 更多。
/// 多选态：关闭 + 已选计数 + 删除，用 AnimatedSwitcher 平滑切换。
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({super.key, required this.controller});

  final ChatController controller;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.appBarHeight);

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedSwitcher(
        duration: AppConstants.animFast,
        child:
            controller.selectionMode.value
                ? _selectionBar(context)
                : _normalBar(context),
      ),
    );
  }

  Widget _normalBar(BuildContext context) {
    final colors = context.colorScheme;
    return AppSearchAppBar(
      key: const ValueKey('normal'),
      title: '',
      onBack: Get.back,
      titleWidget: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.openProfile,
        child: Row(
          children: [
            AppAvatar(
              imageUrl: controller.conversation?.avatarUrl,
              name: controller.title,
              size: 36,
            ),
            const SizedBox(width: AppSizes.paddingSm),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.listPrimary.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    controller.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.conversationTime.copyWith(
                      color: context.tokens.brand,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final colors = context.colorScheme;
    final deleting = controller.isDeletingSelected.value;
    return AppSearchAppBar(
      key: const ValueKey('selection'),
      title: '已选择 ${controller.selectedCount} 项',
      titleStyle: AppTextStyles.pageTitle.copyWith(color: colors.onSurface),
      leadingIcon: Icons.close,
      onBack: controller.exitSelection,
      actions: [
        IconButton(
          icon: deleting
              ? const SizedBox.square(
                  dimension: 20,
                  child: AppLoadingIndicator(),
                )
              : const Icon(Icons.delete_outline),
          color: context.tokens.danger,
          onPressed: deleting ? null : _confirmDeleteSelected,
        ),
      ],
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final count = controller.selectedCount;
    if (count == 0 || controller.isDeletingSelected.value) return;
    final confirmed = await AppConfirmDialog.show(
      title: '删除消息',
      message: '确定仅对自己删除已选择的 $count 条消息吗？',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed == true) await controller.deleteSelected();
  }
}
