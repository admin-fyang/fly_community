/// 编辑个人资料页。
///
/// 按新版 `资料/UI/设置/我的资料修改.html` 还原头像、身份信息、简介和隐私信息。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/avatar/avatar_source_sheet.dart';
import '../../shared/widgets/avatar/editable_avatar.dart';
import '../../shared/widgets/region_code_picker.dart';
import '../../shared/widgets/section_card.dart';
import 'edit_profile_controller.dart';
import 'widgets/settings_scaffold.dart';

/// 编辑资料页面只负责表单渲染，编辑状态由 [EditProfileController] 管理。
class EditProfilePage extends GetView<EditProfileController> {
  const EditProfilePage({super.key});

  static const double _contentMaxWidth = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SettingsScaffold(
      readActivity: controller.pageReads,
      title: '编辑个人资料',
      appBarBackgroundColor: context.isDark
          ? AppColors.darkHomeAppBar
          : colors.surfaceContainerLowest,
      titleStyle: AppTextStyles.pageTitle.copyWith(
        color: colors.onSurface,
        letterSpacing: -0.2,
      ),
      showAppBarDivider: true,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSizes.paddingLg,
        AppSizes.paddingXl,
        AppSizes.paddingLg,
        AppSizes.paddingXl * 4,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      actions: [
        Obx(
          () => TextButton(
            onPressed:
                controller.isSaving.value || controller.isUploadingAvatar.value
                ? null
                : controller.save,
            child: Text(
              controller.isSaving.value
                  ? '保存中'
                  : controller.isUploadingAvatar.value
                  ? '上传中'
                  : '完成',
              style: AppTextStyles.buttonLabel.copyWith(
                color: context.tokens.brand,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.paddingXs),
      ],
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(
                  () => controller.isLoading.value
                      ? const LinearProgressIndicator(minHeight: 2)
                      : const SizedBox.shrink(),
                ),
                _avatarSection(context),
                const SizedBox(height: AppSizes.paddingXl + AppSizes.paddingSm),
                _identitySection(context),
                const SizedBox(height: AppSizes.paddingXl + AppSizes.paddingSm),
                _bioSection(context),
                const SizedBox(height: AppSizes.paddingXl + AppSizes.paddingSm),
                _privacySection(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarSection(BuildContext context) {
    return Center(
      child: Obx(
        () => EditableAvatar(
          size: AppSizes.avatarEditProfile,
          name: controller.displayName,
          imageUrl: controller.avatarUrl,
          localBytes: controller.localAvatarBytes.value,
          isUploading: controller.isUploadingAvatar.value,
          progress: controller.avatarUploadProgress.value,
          borderWidth: 2,
          cameraSize: 36,
          label: controller.isUploadingAvatar.value ? '正在上传头像' : '更换头像',
          onTap: controller.isUploadingAvatar.value
              ? null
              : () => _chooseAvatarSource(context),
        ),
      ),
    );
  }

  Future<void> _chooseAvatarSource(BuildContext context) async {
    final source = await showAvatarPickSourceSheet(context);
    if (source != null) {
      await controller.pickAndUploadAvatar(source);
    }
  }

  Widget _identitySection(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          key: const ValueKey('edit-profile-identity-section'),
          backgroundColor: colors.surfaceContainerLow,
          dividerColor: context.tokens.divider.withValues(alpha: 0.3),
          children: [
            _ProfileTextField(
              label: '名字 - 必填',
              labelColor: context.tokens.brand,
              hintText: '输入您的名字',
              controller: controller.firstNameController,
            ),
            _ProfileTextField(
              hintText: '输入您的姓氏',
              controller: controller.lastNameController,
            ),
            _ProfileTextField(
              fieldKey: const ValueKey('profile-username'),
              label: '用户名',
              hintText: 'username',
              prefixText: '@',
              controller: controller.usernameController,
              onChanged: controller.validateUsername,
              trailing: Obx(
                () => Icon(
                  controller.usernameAvailable.value
                      ? Icons.check_circle
                      : Icons.error,
                  color: controller.usernameAvailable.value
                      ? context.tokens.online
                      : context.tokens.danger,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.paddingXs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
          child: Text(
            '您可以设置一个用户名。如果设置了用户名，其他人可以通过此用户名找到您并与您联系，而无需知道您的电话号码。',
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bioSection(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          key: const ValueKey('edit-profile-bio-section'),
          backgroundColor: colors.surfaceContainerLow,
          children: [
            _ProfileTextField(
              fieldKey: const ValueKey('profile-bio'),
              label: '个人简介',
              hintText: '关于您的简短介绍...',
              controller: controller.bioController,
              maxLines: 3,
              textStyle: AppTextStyles.messageBody,
            ),
          ],
        ),
        const SizedBox(height: AppSizes.paddingXs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
          child: Text(
            '此简介将显示在您的资料页面。',
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _privacySection(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
          child: Text(
            '隐私与联系方式',
            style: AppTextStyles.metadata.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.paddingLg),
        SectionCard(
          key: const ValueKey('edit-profile-privacy-section'),
          backgroundColor: colors.surfaceContainerLow,
          dividerColor: context.tokens.divider.withValues(alpha: 0.3),
          children: [
            InkWell(
              key: const ValueKey('birthday-row'),
              onTap: () => _selectBirthday(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.paddingLg,
                  vertical: AppSizes.paddingMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '生日',
                            style: AppTextStyles.metadata.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Obx(
                            () => Text(
                              controller.birthdayText,
                              style: AppTextStyles.listPrimary.copyWith(
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Obx(
                      () => Text(
                        controller.birthdayVisibilityLabel,
                        style: AppTextStyles.metadata.copyWith(
                          color: context.tokens.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.paddingXs),
                    Icon(
                      Icons.chevron_right,
                      color: context.tokens.brand,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.paddingLg,
                vertical: AppSizes.paddingMd,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '手机号码',
                          style: AppTextStyles.metadata.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Obx(
                          () => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RegionCodePickerButton(
                                value: controller.regionCode.value,
                                onChanged: controller.setRegionCode,
                                compact: true,
                              ),
                              Flexible(
                                child: Text(
                                  controller.phoneText,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.listPrimary.copyWith(
                                    color: colors.onSurface,
                                    // fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Obx(
                    () => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.paddingSm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: controller.phoneVerified
                            ? context.tokens.online.withValues(alpha: 0.12)
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          AppSizes.radiusFull,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            controller.phoneVerified
                                ? Icons.verified
                                : Icons.info_outline,
                            color: controller.phoneVerified
                                ? context.tokens.online
                                : colors.onSurfaceVariant,
                            size: 14,
                          ),
                          const SizedBox(width: AppSizes.paddingXs),
                          Text(
                            controller.phoneVerified ? '已验证' : '未验证',
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: controller.phoneVerified
                                  ? context.tokens.online
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectBirthday(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: controller.birthday.value ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: '选择生日',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected != null) controller.updateBirthday(selected);
  }
}

/// 新版资料项统一为垂直标签 + 无边框输入，选中反馈由卡片表面承担。
class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.hintText,
    required this.controller,
    this.fieldKey,
    this.label,
    this.labelColor,
    this.prefixText,
    this.maxLines = 1,
    this.onChanged,
    this.trailing,
    this.textStyle,
  });

  final String hintText;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? label;
  final Color? labelColor;
  final String? prefixText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.paddingLg,
        vertical: AppSizes.paddingMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label!,
                    style: AppTextStyles.badgeLabel.copyWith(
                      color: labelColor ?? colors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingXs),
                ],
                TextField(
                  ///清理输入框的所有边距
                  scrollPadding: EdgeInsets.zero,
                  key: fieldKey,
                  controller: controller,
                  maxLines: maxLines,
                  onChanged: onChanged,
                  style: (textStyle ?? AppTextStyles.listPrimary).copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: hintText,
                    prefixText: prefixText,
                    prefixStyle: AppTextStyles.listPrimary.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    hintStyle: AppTextStyles.listPrimary.copyWith(
                      // Telegram-iOS Night itemInputField placeholder = #8F8F8F.
                      // Keep Light mode's existing outline-derived behavior.
                      color: context.isDark
                          ? const Color(0xFF8F8F8F)
                          : colors.outline.withValues(alpha: 0.5),
                    ),

                    ///清理输入框的所有边距
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSizes.paddingMd),
            trailing!,
          ],
        ],
      ),
    );
  }
}
