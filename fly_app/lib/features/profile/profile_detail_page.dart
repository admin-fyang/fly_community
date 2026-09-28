/// 用户资料详情页。
///
/// 好友与陌生人共用,由 isStranger 决定四宫格/信息卡/危险操作等布局差异。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/profile_detail_model.dart';
import '../../shared/widgets/app_switch_row.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../../shared/widgets/section_card.dart';
import 'profile_controller.dart';
import 'widgets/profile_action_grid.dart';
import 'widgets/profile_hero.dart';
import 'widgets/profile_info_row.dart';

/// 用户详情页(好友 / 陌生人共用)
///
/// Hero + 简介卡恒显示;好友态另有四宫格、信息卡与危险操作,
/// 陌生人态仅显示「添加为联系人 / 发送消息」行动项。布局由 [ProfileDetailModel.isStranger] 驱动。
class ProfileDetailPage extends GetView<ProfileController> {
  const ProfileDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.version.value;
      final detail = controller.detail;
      return AppPageScaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: context.semanticColors.backgroundGrouped,
        appBar: AppSearchAppBar(
          title: detail.name,
          onBack: Get.back,
          backgroundColor: context.semanticColors.backgroundGrouped,
          titleStyle: AppTextStyles.pageTitleMobile.copyWith(
            color: context.semanticColors.textPrimary,
          ),
          dividerColor: context.semanticColors.separator,
        ),
        body: ListView(
          padding: (const EdgeInsets.only(
            bottom: AppSizes.paddingXl,
          )).add(EdgeInsets.only(top: appTopBarInset(context))),
          children: [
            ProfileHero(detail: detail),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingLg,
              ),
              child: detail.isStranger
                  ? _strangerBody(context, detail)
                  : _friendBody(context, detail),
            ),
          ],
        ),
      );
    });
  }

  // ===== 好友态主体 =====
  Widget _friendBody(BuildContext context, ProfileDetailModel d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileActionGrid(
          actions: [
            ProfileAction(
              Icons.chat_bubble_outline,
              '消息',
              controller.sendMessage,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sectionGap),
        _profileCard(context, d),
        const SizedBox(height: AppSizes.sectionGap),
        _contactSettingsCard(context),
        const SizedBox(height: AppSizes.sectionGap),
        _infoCard(context, d),
        const SizedBox(height: AppSizes.sectionGap),
        SectionCard(
          children: [
            _dangerRow(
              context,
              Icons.delete_outline,
              '删除好友',
              controller.confirmDelete,
            ),
            Obx(
              () => _dangerRow(
                context,
                Icons.block,
                controller.isBlocked.value ? '取消拉黑' : '拉黑用户',
                controller.confirmBlock,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===== 陌生人态主体 =====
  Widget _strangerBody(BuildContext context, ProfileDetailModel d) {
    final canAddFriend = controller.canAddFriend;
    final canSendMessage = controller.canSendMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileCard(context, d),
        if (canAddFriend || canSendMessage) ...[
          const SizedBox(height: AppSizes.sectionGap),
          SectionCard(
            children: [
              if (canAddFriend)
                _actionRow(
                  context,
                  Icons.person_add_alt,
                  '添加为联系人',
                  controller.showAddContactDialog,
                ),
              if (canSendMessage)
                _actionRow(
                  context,
                  Icons.chat_bubble_outline,
                  '发送消息',
                  controller.sendMessage,
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ===== 简介卡:个人简介 + 用户名 =====
  Widget _profileCard(BuildContext context, ProfileDetailModel d) {
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSizes.paddingLg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.bio.isEmpty ? '未设置' : d.bio,
                      style: AppTextStyles.messageBody,
                    ),
                    const SizedBox(height: AppSizes.paddingXs),
                    Text('个人简介', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.username,
                        style: AppTextStyles.messageBody.copyWith(
                          color: context.semanticColors.accent,
                        ),
                      ),
                      const SizedBox(height: AppSizes.paddingXs),
                      Text('用户名', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
        ),
      ],
    );
  }

  // ===== 信息卡:手机号 / 上次上线 / 地区 / 生日 / 注册时间 / 共同群组 =====
  Widget _infoCard(BuildContext context, ProfileDetailModel d) {
    return SectionCard(
      children: [
        ProfileInfoRow(label: '手机号', value: controller.phoneText),
        ProfileInfoRow(label: '上次上线', value: controller.lastSeenText),
        ProfileInfoRow(label: '地区', value: d.region),
        ProfileInfoRow(label: '生日', value: controller.birthdayText),
        ProfileInfoRow(label: '注册时间', value: controller.registerTimeText),
      ],
    );
  }

  Widget _contactSettingsCard(BuildContext context) {
    return SectionCard(
      children: [
        Obx(
          () => _valueRow(
            context,
            Icons.edit_note,
            '备注',
            controller.remark.value.isEmpty ? '未设置' : controller.remark.value,
            controller.editRemark,
          ),
        ),
        Obx(
          () => AppSwitchRow(
            label: '置顶聊天',
            value: controller.isPinned.value,
            onChanged: controller.togglePinned,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingLg,
              vertical: AppSizes.paddingSm,
            ),
          ),
        ),
        Obx(
          () => AppSwitchRow(
            label: '消息免打扰',
            value: controller.isMuted.value,
            onChanged: controller.toggleMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingLg,
              vertical: AppSizes.paddingSm,
            ),
          ),
        ),
        _valueRow(
          context,
          Icons.delete_sweep_outlined,
          '清空聊天记录',
          '',
          controller.confirmClearConversation,
        ),
      ],
    );
  }

  // ===== 行模板 =====
  Widget _actionRow(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final semantic = context.semanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(semantic.surfacePressed),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingLg),
          child: Row(
            children: [
              Icon(icon, color: semantic.accent),
              const SizedBox(width: AppSizes.paddingMd),
              Text(
                label,
                style: AppTextStyles.buttonLabel.copyWith(
                  color: semantic.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dangerRow(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final semantic = context.semanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          semantic.destructive.withValues(alpha: 0.06),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingLg),
          child: Row(
            children: [
              Icon(icon, color: semantic.destructive),
              const SizedBox(width: AppSizes.paddingMd),
              Text(
                label,
                style: AppTextStyles.messageBody.copyWith(
                  color: semantic.destructive,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _valueRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    final semantic = context.semanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(semantic.surfacePressed),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingLg),
          child: Row(
            children: [
              Icon(icon, color: semantic.textTertiary),
              const SizedBox(width: AppSizes.paddingMd),
              Text(
                label,
                style: AppTextStyles.messageBody.copyWith(
                  color: semantic.textPrimary,
                ),
              ),
              const SizedBox(width: AppSizes.paddingMd),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.metadata.copyWith(
                    color: semantic.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingXs),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: semantic.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
