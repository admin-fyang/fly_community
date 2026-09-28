/// 联系人列表项组件。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/contact_model.dart';
import '../../../shared/widgets/avatar/app_avatar.dart';
import '../../../shared/widgets/interaction/app_pressable.dart';

class ContactItem extends StatelessWidget {
  const ContactItem({super.key, required this.contact, this.onTap});

  /// 固定行高同时参与索引跳转计算，不依赖系统字体缩放改变。
  static const double height = 64;

  final ContactModel contact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final statusColor =
        contact.isOnline ? context.tokens.online : semantic.textSecondary;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.12,
      child: AppPressable(
        semanticLabel: contact.name,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
            child: Row(
              children: [
                AppAvatar(
                  imageUrl: contact.avatarUrl,
                  name: contact.name,
                  size: 44,
                ),
                const SizedBox(width: AppSizes.paddingItem),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
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
                      const SizedBox(height: 2),
                      Text(
                        contact.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                          fontSize: 13,
                          height: 18 / 13,
                          forceStrutHeight: true,
                        ),
                        style: AppTextStyles.metadata.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
