/// 通知列表项组件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/enums/notification_kind.dart';
import '../../../data/models/notification_model.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';
import '../../../shared/widgets/interaction/app_pressable.dart';

class NotificationItem extends StatelessWidget {
  const NotificationItem({super.key, required this.notification, this.onTap});

  final NotificationModel notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final n = notification;
    final iconColor = n.kind == NotificationKind.system
        ? semantic.textSecondary
        : semantic.accent;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.12,
      child: AppPressable(
        semanticLabel: n.title,
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
            child: Row(
              children: [
                _avatar(n, semantic, iconColor),
                const SizedBox(width: AppSizes.paddingItem),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          fontSize: 16,
                          height: 22 / 16,
                          forceStrutHeight: true,
                        ),
                        style: AppTextStyles.listPrimary.copyWith(
                          color: semantic.textPrimary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        n.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          forceStrutHeight: true,
                        ),
                        style: AppTextStyles.metadata.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.paddingMd),
                _trailing(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    final semantic = context.semanticColors;
    if (notification.badge > 0) {
      final text = notification.badge > 99 ? '99+' : '${notification.badge}';
      return Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: semantic.accent,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
        alignment: Alignment.center,
        child: MediaQuery.withNoTextScaling(
          child: Text(
            text,
            style: AppTextStyles.badgeLabel.copyWith(color: Colors.white),
          ),
        ),
      );
    }
    if (notification.timeText.isNotEmpty) {
      return Text(
        notification.timeText,
        strutStyle: const StrutStyle(
          fontSize: 12.5,
          height: 16 / 12.5,
          forceStrutHeight: true,
        ),
        style: AppTextStyles.conversationTime.copyWith(
          color: semantic.textTertiary,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _avatar(
    NotificationModel n,
    AppSemanticColors semantic,
    Color iconColor,
  ) {
    return switch (n.kind) {
      NotificationKind.friendRequest => AppAvatar(
        imageUrl: n.actorAvatarUrl,
        name: n.actorName,
        size: 42,
      ),
      NotificationKind.system => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: semantic.surfaceElevated,
          borderRadius: BorderRadius.circular(11),
        ),
        // child: Icon(n.kind.icon, size: 20, color: iconColor),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFE8873A).withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            'assets/icons/chat/system_announcement.svg',
            width: 21,
            height: 21,
            colorFilter: ColorFilter.mode(
              const Color(0xFFE8873A),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    };
  }
}
