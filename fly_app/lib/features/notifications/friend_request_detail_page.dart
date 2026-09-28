/// 好友申请详情页。
///
/// 基于陌生人资料页的信息密度和视觉结构，额外承载申请备注与审核动作。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../profile/widgets/profile_hero.dart';
import 'friend_request_detail_controller.dart';

class FriendRequestDetailPage extends GetView<FriendRequestDetailController> {
  const FriendRequestDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.version.value;
      final detail = controller.detail;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Get.back(result: controller.hasChanged.value);
        },
        child: AppPageScaffold(
          extendBodyBehindAppBar: true,
          readActivity: controller.pageReads,
          backgroundColor: context.semanticColors.backgroundGrouped,
          appBar: AppSearchAppBar(
            title: detail.name,
            onBack: () => Get.back(result: controller.hasChanged.value),
            titleStyle: AppTextStyles.pageTitleMobile.copyWith(
              color: context.colorScheme.onSurface,
            ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _requestCard(context),
                    const SizedBox(height: AppSizes.sectionGap),
                    _profileCard(context),
                    const SizedBox(height: AppSizes.sectionGap),
                    _actionCard(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _profileCard(BuildContext context) {
    final detail = controller.detail;
    final colors = context.colorScheme;
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
                      detail.bio.isEmpty ? '暂无简介' : detail.bio,
                      style: AppTextStyles.messageBody.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSizes.paddingXs),
                    Text('个人简介', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: controller.showQrCode,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.username.isEmpty ? '未设置' : detail.username,
                        style: AppTextStyles.messageBody.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSizes.paddingXs),
                      Text('用户名', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.qr_code_2, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _requestCard(BuildContext context) {
    final remark = controller.detailReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.reasonTitle,
          style: AppTextStyles.metadata.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSizes.paddingMd),
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                remark.isEmpty ? controller.emptyReasonText : remark,
                textAlign: TextAlign.left,
                style: AppTextStyles.listPrimary.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionCard(BuildContext context) {
    return Obx(() {
      final isHandling = controller.isHandling.value;
      final canHandle = controller.canHandle;
      final resultAction = controller.resultAction.value;
      if (resultAction == 'accepted' || resultAction == 'rejected') {
        return _animatedResultActions(context, resultAction);
      }
      if (controller.isFriendRejected) {
        return const SizedBox.shrink();
      }
      if (!canHandle) {
        return _handledStatusCard(context);
      }

      return Row(
        children: [
          Expanded(
            child: _actionButton(
              context,
              '拒绝',
              filled: false,
              onTap: isHandling ? null : controller.showRejectDialog,
            ),
          ),
          const SizedBox(width: AppSizes.paddingMd),
          Expanded(
            flex: 2,
            child: _actionButton(
              context,
              '同意',
              filled: true,
              onTap: isHandling ? null : controller.accept,
            ),
          ),
        ],
      );
    });
  }

  Widget _handledStatusCard(BuildContext context) {
    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingLg),
        child: Text(
          _statusText(controller.notification.actionStatus),
          textAlign: TextAlign.center,
          style: AppTextStyles.listPrimary.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _animatedResultActions(BuildContext context, String action) {
    final targetAcceptedWidth = action == 'accepted' ? 1.0 : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 2 / 3, end: targetAcceptedWidth),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          onEnd: controller.markResultTextReady,
          builder: (context, acceptedWidthRatio, _) {
            final gap = acceptedWidthRatio == 0 || acceptedWidthRatio == 1
                ? 0.0
                : AppSizes.paddingMd;
            final availableWidth = constraints.maxWidth - gap;
            final acceptWidth = availableWidth * acceptedWidthRatio;
            final rejectWidth = availableWidth - acceptWidth;
            return Row(
              children: [
                SizedBox(
                  width: rejectWidth,
                  child: rejectWidth <= 1
                      ? const SizedBox.shrink()
                      : _actionButton(
                          context,
                          _resultLabel('rejected', fallback: '拒绝'),
                          filled: action == 'rejected',
                          danger: action == 'rejected',
                          onTap: null,
                        ),
                ),
                if (gap > 0) const SizedBox(width: AppSizes.paddingMd),
                SizedBox(
                  width: acceptWidth,
                  child: acceptWidth <= 1
                      ? const SizedBox.shrink()
                      : _actionButton(
                          context,
                          _resultLabel('accepted', fallback: '同意'),
                          filled: true,
                          danger: false,
                          onTap: null,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _resultLabel(String action, {required String fallback}) {
    if (controller.resultAction.value != action ||
        !controller.resultTextReady.value) {
      return fallback;
    }
    return action == 'accepted' ? '已同意' : '已拒绝';
  }

  Widget _actionButton(
    BuildContext context,
    String label, {
    required bool filled,
    bool danger = false,
    required VoidCallback? onTap,
  }) {
    final brand = context.tokens.brand;
    final dangerColor = context.tokens.danger;
    final activeColor = danger ? dangerColor : brand;
    final filledBackground = filled
        ? activeColor
        : context.colorScheme.surfaceContainerHighest;
    final filledForeground = filled
        ? Colors.white
        : context.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: filledBackground,
          foregroundColor: filledForeground,
          disabledBackgroundColor: filledBackground,
          disabledForegroundColor: filledForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          ),
        ),
        child: Text(label),
      ),
    );
  }

  String _statusText(String status) {
    return switch (status) {
      'accepted' => '已同意',
      'rejected' => '已拒绝',
      _ => '已处理',
    };
  }
}
