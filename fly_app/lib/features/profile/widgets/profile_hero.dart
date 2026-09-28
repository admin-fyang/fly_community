/// Profile hero: avatar, name and presence.
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/profile_detail_model.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';

class ProfileHero extends StatelessWidget {
  const ProfileHero({super.key, required this.detail});

  final ProfileDetailModel detail;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
      child: Column(
        children: [
          _avatar(context),
          const SizedBox(height: AppSizes.paddingLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  detail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.pageTitle.copyWith(
                    color: semantic.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (detail.verified) ...[
                const SizedBox(width: AppSizes.paddingXs),
                Icon(
                  Icons.verified,
                  size: 18,
                  color: context.isDark ? Colors.white : semantic.accent,
                ),
              ],
            ],
          ),
          if (detail.presence.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              detail.presence,
              style: AppTextStyles.metadata.copyWith(
                color: semantic.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    return SizedBox(
      width: AppSizes.avatarProfile,
      height: AppSizes.avatarProfile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppAvatar(
            imageUrl: detail.avatarUrl,
            name: detail.name,
            size: AppSizes.avatarProfile,
          ),
          if (detail.isOnline)
            Positioned(
              right: 2,
              bottom: 3,
              child: Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Telegram-iOS Night ChatList.onlineDotColor = #4CC91F.
                  // Only the actual presence dot uses this role; success/call
                  // greens remain on the product's existing semantic colors.
                  color: context.isDark
                      ? const Color(0xFF4CC91F)
                      : context.tokens.online,
                  border: Border.all(
                    color: context.semanticColors.backgroundGrouped,
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
