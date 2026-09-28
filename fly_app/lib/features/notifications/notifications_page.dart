/// 消息通知页。
///
/// 独立列表页(抽屉入口):好友请求/群邀请/系统通知,支持顶栏搜索过滤。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/empty/app_empty_state.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../../shared/widgets/skeleton/app_skeleton.dart';
import 'notifications_controller.dart';
import 'widgets/notification_item.dart';

/// 消息通知页(系统通知列表 + 顶栏搜索切换)
class NotificationsPage extends GetView<NotificationsController> {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      readActivity: controller.pageReads,
      // 顶栏走全局统一的「普通 ↔ 搜索」切换(与联系人页一致)
      appBar: AppSearchAppBar(
        title: '消息通知',
        titleStyle: AppTextStyles.pageTitleMobile.copyWith(
          color: context.colorScheme.onSurface,
        ),
        mode: controller.topBarMode,
        onBack: Get.back,
        onOpenSearch: controller.openSearch,
        onCloseSearch: controller.closeSearch,
        onChanged: controller.updateKeyword,
        searchHint: '搜索系统通知',
      ),
      body: Obx(() {
        final list = controller.filtered;
        final showInitialSkeleton = controller.isLoading.value && list.isEmpty;
        if (showInitialSkeleton) return const _NotificationSkeletonList();
        if (list.isEmpty) return _empty(context);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 240) {
              controller.loadMore();
            }
            return false;
          },
          child: ListView.builder(
            padding: EdgeInsets.only(top: appTopBarInset(context)),
            itemCount: list.length + 1,
            itemBuilder: (_, i) => i >= list.length
                ? _loadMoreFooter(context)
                : NotificationItem(
                    notification: list[i],
                    onTap: () => controller.openNotification(list[i]),
                  ),
          ),
        );
      }),
    );
  }

  Widget _loadMoreFooter(BuildContext context) {
    return Obx(
      () => SizedBox(
        height: 72,
        child: controller.hasMore.value
            ? Center(
                child: Text(
                  '上拉加载更多',
                  style: AppTextStyles.metadata.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return const Center(child: AppEmptyState(message: '没有相关通知'));
  }
}

/// 消息通知页首次加载骨架屏。
///
/// 只模拟通知列表主体，不参与分页加载，也不改变搜索过滤逻辑。
class _NotificationSkeletonList extends StatelessWidget {
  const _NotificationSkeletonList();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: ListView.builder(
        padding: EdgeInsets.only(top: appTopBarInset(context)),
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => const _NotificationSkeletonItem(),
      ),
    );
  }
}

class _NotificationSkeletonItem extends StatelessWidget {
  const _NotificationSkeletonItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingSm,
      ),
      child: Row(
        children: [
          const AppSkeletonBlock.circle(size: AppSizes.avatarMd),
          const SizedBox(width: AppSizes.paddingLg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeletonBlock(width: 128, height: 13),
                const SizedBox(height: 8),
                const AppSkeletonBlock(width: 210, height: 10),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.paddingMd),
          const AppSkeletonBlock(width: 44, height: 10),
        ],
      ),
    );
  }
}
