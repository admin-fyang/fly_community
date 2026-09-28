/// 搜索结果·用户项组件。
///
/// 展示用户头像、昵称与用户名,点击进入好友/陌生人资料。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/contact_model.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';
import '../../../shared/widgets/skeleton/app_skeleton.dart';

/// 搜索结果:用户/联系人行(头像 + 昵称 + @用户名 + 好友标记/箭头)
class SearchUserItem extends StatelessWidget {
  const SearchUserItem({
    super.key,
    required this.contact,
    required this.isFriend,
    this.onTap,
  });

  final ContactModel contact;
  final bool isFriend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingLg,
          vertical: AppSizes.paddingMd,
        ),
        child: Row(
          children: [
            AppAvatar(
              imageUrl: contact.avatarUrl,
              name: contact.name,
              size: AppSizes.avatarMd,
            ),
            const SizedBox(width: AppSizes.paddingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.listPrimary.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // contact.username ?? '@user_${contact.id}',
                    contact.username ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.metadata.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.paddingSm),
            if (isFriend)
              _friendBadge(context)
            else
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _friendBadge(BuildContext context) {
    final brand = context.tokens.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: brand.withValues(alpha: 0.4)),
      ),
      child: Text('好友', style: AppTextStyles.badgeLabel.copyWith(color: brand)),
    );
  }
}

/// 搜索用户项的骨架屏占位
class SearchUserItemSkeleton extends StatelessWidget {
  const SearchUserItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingMd,
      ),
      child: Row(
        children: [
          // 头像占位
          const AppSkeletonBlock.circle(size: AppSizes.avatarMd),
          const SizedBox(width: AppSizes.paddingMd),
          // 信息占位
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeletonBlock(width: 120, height: 12),
                const SizedBox(height: 6),
                const AppSkeletonBlock(width: 80, height: 8),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.paddingSm),
          // 右侧箭头或标记占位
          const AppSkeletonBlock(width: 24, height: 24),
        ],
      ),
    );
  }
}

/// 独立的骨架屏列表，使用全局骨架动画保持各页面加载反馈一致。
class SearchSkeletonList extends StatelessWidget {
  const SearchSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: ListView.builder(
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(), // 骨架屏加载时一般不滚动
        itemBuilder: (context, index) {
          return const SearchUserItemSkeleton();
        },
      ),
    );
  }
}
