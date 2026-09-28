/// 全局搜索页。
///
/// 统一搜索栏 + 空态入口(我的名片/扫一扫)+ 用户/群组命中结果。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/empty/app_empty_state.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import 'search_controller.dart';
import 'widgets/search_user_item.dart';

/// 全局搜索页
///
/// 空态:搜索类别 + 最近搜索;输入后按用户/群分组展示结果,无匹配显示空态。
class SearchPage extends GetView<GlobalSearchController> {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      isReading: () => controller.isLoading.value,
      appBar: AppSearchAppBar(
        title: '搜索',
        searchOnly: true,
        searchController: controller.textController,
        onCloseSearch: Get.back,
        onChanged: controller.onChanged,
        searchHint: '搜索用户...',
      ),
      body: Obx(() {
        if (!controller.hasKeyword) return _idleView(context);
        if (controller.isLoading.value && !controller.hasResults) {
          return Padding(
            padding: EdgeInsets.only(top: appTopBarInset(context)),
            child: const SearchSkeletonList(),
          );
        }
        if (!controller.hasResults) return _emptyView(context);
        return _resultsView(context);
      }),
    );
  }

  // ===== 结果态 =====
  Widget _resultsView(BuildContext context) {
    final users = controller.userResults;
    return ListView(
      padding: EdgeInsets.only(top: appTopBarInset(context)),
      children: [
        if (users.isNotEmpty) ...[
          _sectionHeader(context, '联系人/用户', users.length),
          for (final u in users)
            SearchUserItem(
              contact: u,
              isFriend: controller.isFriend(u),
              onTap: () => controller.openUser(u),
            ),
        ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    final colors = context.colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surfaceContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          Text(
            '匹配结果($count)',
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ===== 无匹配空态 =====
  Widget _emptyView(BuildContext context) {
    final error = controller.errorMessage.value;
    return Center(
      child: AppEmptyState(
        message: error.isEmpty ? '未找到匹配项' : error,
        description: error.isEmpty
            ? '尝试输入不同的关键词、手机号或用户名，确保拼写正确。'
            : '请检查网络后重新搜索。',
      ),
    );
  }

  // ===== 空态(未输入):搜索类别 + 最近搜索 =====
  Widget _idleView(BuildContext context) {
    return ListView(
      padding: (const EdgeInsets.symmetric(
        vertical: AppSizes.paddingLg,
      )).add(EdgeInsets.only(top: appTopBarInset(context))),
      children: [
        _groupLabel(context, '搜索类别'),
        const SizedBox(height: AppSizes.paddingMd),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
          child: Wrap(
            spacing: AppSizes.paddingSm,
            runSpacing: AppSizes.paddingSm,
            children: [for (final c in controller.categories) _tag(context, c)],
          ),
        ),

        const SizedBox(height: AppSizes.paddingXl),
        _groupLabel(context, '最近搜索'),
        for (final keyword in controller.recentKeywords)
          _recentKeywordItem(context, keyword),
        if (controller.recentKeywords.isEmpty)
          const AppEmptyState(
            message: '暂无最近搜索',
            imageSize: 64,
            padding: EdgeInsets.all(AppSizes.paddingMd),
          ),
      ],
    );
  }

  Widget _recentKeywordItem(BuildContext context, String keyword) {
    final colors = context.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => controller.selectRecentKeyword(keyword),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLg,
            vertical: AppSizes.paddingMd,
          ),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: AppSizes.iconSm,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSizes.paddingMd),
              Expanded(
                child: Text(
                  keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.listPrimary.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.paddingMd),
              Icon(
                Icons.search,
                size: AppSizes.iconSm,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSizes.paddingLg,
      0,
      AppSizes.paddingLg,
      AppSizes.paddingSm,
    ),
    child: Text(
      text,
      style: AppTextStyles.metadata.copyWith(
        color: context.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _categoryButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final colors = context.colorScheme;
    final surface = context.isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          child: Row(
            children: [
              Icon(icon, color: context.tokens.brand),
              const SizedBox(width: AppSizes.paddingMd),
              Text(
                label,
                style: AppTextStyles.listPrimary.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String text) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingMd,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Text(
        text,
        style: AppTextStyles.metadata.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
