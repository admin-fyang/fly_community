/// 新版注册页。
///
/// 页面按系统配置在两步与三步之间切换，只负责展示状态和转发事件；所有校验、
/// 接口调用及配置变化处理均由 [RegisterController] 完成。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flychat/features/auth/widgets/auth_brand_header.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../shared/widgets/icons/airplane_float.dart';
import '../../shared/widgets/region_code_picker.dart';
import 'register_controller.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_scale_scope.dart';
import 'widgets/register_step_indicator.dart';
import 'widgets/register_text_field.dart';

class RegisterPage extends GetView<RegisterController> {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthTextScaleScope(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.previousStep();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(onBack: controller.previousStep),
                Expanded(
                  child: Obx(() {
                    final step = controller.currentStep.value;
                    final steps = controller.visibleSteps;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.paddingXl,
                        AppSizes.paddingLg,
                        AppSizes.paddingXl,
                        AppSizes.paddingXl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            children: [
                              RegisterStepIndicator(
                                stepCount: steps.length,
                                currentIndex: controller.currentStepIndex,
                              ),
                              const SizedBox(height: 44),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0.03, 0),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: KeyedSubtree(
                                  key: ValueKey(step),
                                  child: switch (step) {
                                    RegistrationStep.account => _AccountStep(
                                      controller: controller,
                                    ),
                                    RegistrationStep.verification =>
                                      _VerificationStep(controller: controller),
                                    RegistrationStep.profile => _ProfileStep(
                                      controller: controller,
                                    ),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          /*Text(
            '注册账号',
            style: AppTextStyles.navTitle.copyWith(
              color: context.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          Positioned(
            left: AppSizes.paddingXs,
            child: IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
            ),
          ),*/
        ],
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  const _AccountStep({required this.controller});

  final RegisterController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        /*SvgPicture.asset('assets/icons/logo.svg', width: 92, height: 92),
        const SizedBox(height: AppSizes.paddingXl),
        const _StepIntro(title: '创建账号', subtitle: '设置您的登录账号和密码'),*/

        /*AirplaneFloat(
          child: SvgPicture.asset(
            'assets/icons/logo_02.svg',
          ),
        ),*/

        const AuthBrandHeader(
          title: '创建账号',
          subtitle: '设置您的登录账号和密码',
          logo: true,
        ),
        const SizedBox(height: AppSizes.paddingXl),
        Obx(() {
          final state = controller.usernameAvailability.value;
          return RegisterTextField(
            controller: controller.usernameController,
            focusNode: controller.usernameFocusNode,
            hint: '用户名（5–32位，字母开头）',
            icon: Icons.alternate_email_rounded,
            errorText: controller.usernameError.value,
            supportingText: state == UsernameAvailabilityState.failed
                ? controller.usernameAvailabilityMessage
                : null,
            suffix: _UsernameAvailabilityIcon(state: state),
            maxLength: 32,
            textInputAction: TextInputAction.next,
            onChanged: controller.onUsernameChanged,
          );
        }),
        const SizedBox(height: AppSizes.paddingLg),
        Obx(
          () => RegisterTextField(
            controller: controller.passwordController,
            hint: '密码（8–64位，包含字母和数字）',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            errorText: controller.passwordError.value,
            maxLength: 64,
            textInputAction: TextInputAction.next,
            onChanged: (_) => controller.passwordError.value = null,
          ),
        ),
        const SizedBox(height: AppSizes.paddingLg),
        Obx(
          () => RegisterTextField(
            controller: controller.confirmPasswordController,
            hint: '确认密码',
            icon: Icons.lock_outline_rounded,
            obscure: true,
            errorText: controller.confirmPasswordError.value,
            maxLength: 64,
            textInputAction: TextInputAction.done,
            onChanged: (_) => controller.confirmPasswordError.value = null,
            onSubmitted: (_) => controller.nextFromAccount(),
          ),
        ),
        const SizedBox(height: AppSizes.paddingXl),
        AuthPrimaryButton(
          label: '下一步',
          onPressed: controller.nextFromAccount,
          showTrailingIcon: false,
        ),
        // const SizedBox(height: 42),
        _LoginLink(onTap: controller.previousStep),
      ],
    );
  }
}

class _VerificationStep extends StatelessWidget {
  const _VerificationStep({required this.controller});

  final RegisterController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 72,
          color: context.tokens.brand,
        ),
        const SizedBox(height: AppSizes.paddingXl),
        const _StepIntro(title: '验证联系方式', subtitle: '完成验证后可用于登录和账号安全'),
        const SizedBox(height: AppSizes.paddingXl),
        if (controller.needsPhoneVerification) ...[
          Obx(
            () => RegisterTextField(
              controller: controller.phoneController,
              focusNode: controller.phoneFocusNode,
              hint: '手机号',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              errorText: controller.phoneError.value,
              prefix: RegionCodePickerButton(
                value: controller.regionCode.value,
                onChanged: controller.setRegionCode,
              ),
              textInputAction: TextInputAction.next,
              onChanged: controller.onPhoneChanged,
            ),
          ),
          const SizedBox(height: AppSizes.paddingLg),
          Obx(
            () => RegisterTextField(
              controller: controller.phoneCodeController,
              focusNode: controller.phoneCodeFocusNode,
              hint: '短信验证码',
              icon: Icons.shield_outlined,
              keyboardType: TextInputType.number,
              maxLength: 6,
              errorText: controller.phoneCodeError.value,
              suffix: _CodeButton(
                loading: controller.isSendingPhoneCode.value,
                seconds: controller.phoneResendSeconds.value,
                onPressed: () =>
                    controller.sendCode(RegistrationContactChannel.phone),
              ),
              onChanged: (_) => controller.phoneCodeError.value = null,
            ),
          ),
        ],
        if (controller.needsPhoneVerification &&
            controller.needsEmailVerification)
          const SizedBox(height: AppSizes.paddingLg),
        if (controller.needsEmailVerification) ...[
          Obx(
            () => RegisterTextField(
              controller: controller.emailController,
              focusNode: controller.emailFocusNode,
              hint: '邮箱',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              errorText: controller.emailError.value,
              textInputAction: TextInputAction.next,
              onChanged: controller.onEmailChanged,
            ),
          ),
          const SizedBox(height: AppSizes.paddingLg),
          Obx(
            () => RegisterTextField(
              controller: controller.emailCodeController,
              focusNode: controller.emailCodeFocusNode,
              hint: '邮箱验证码',
              icon: Icons.shield_outlined,
              keyboardType: TextInputType.number,
              maxLength: 6,
              errorText: controller.emailCodeError.value,
              suffix: _CodeButton(
                loading: controller.isSendingEmailCode.value,
                seconds: controller.emailResendSeconds.value,
                onPressed: () =>
                    controller.sendCode(RegistrationContactChannel.email),
              ),
              onChanged: (_) => controller.emailCodeError.value = null,
              onSubmitted: (_) => controller.nextFromVerification(),
            ),
          ),
        ],
        const SizedBox(height: AppSizes.paddingXl),
        AuthPrimaryButton(
          label: '下一步',
          onPressed: controller.nextFromVerification,
          showTrailingIcon: false,
        ),
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({required this.controller});

  final RegisterController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Obx(() {
          // 必须在 Obx 回调内直接读取 Rx，GetX 才能建立响应式依赖。
          return _SelectedAvatar(
            localAvatar: controller.selectedLocalAvatar.value,
            defaultAvatarPath: controller.selectedAvatarPath.value,
            onTap: controller.pickAvatarFromGallery,
          );
        }),
        const SizedBox(height: AppSizes.paddingLg),
        const _StepIntro(title: '完善资料', subtitle: '设置您的昵称和头像'),
        const SizedBox(height: AppSizes.paddingXl),
        Text(
          '选择一个头像',
          style: AppTextStyles.listTitle.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSizes.paddingLg),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: RegisterController.defaultAvatarPaths.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSizes.paddingItem),
            itemBuilder: (context, index) {
              final path = RegisterController.defaultAvatarPaths[index];
              return Obx(() {
                final selected =
                    controller.selectedLocalAvatar.value == null &&
                    controller.selectedAvatarPath.value == path;
                return _AvatarChoice(
                  path: path,
                  selected: selected,
                  onTap: () => controller.selectDefaultAvatar(path),
                );
              });
            },
          ),
        ),
        const SizedBox(height: AppSizes.paddingLg),
        /*Obx(
          () => TextButton.icon(
            onPressed: controller.isPickingAvatar.value
                ? null
                : controller.pickAvatarFromGallery,
            icon: controller.isPickingAvatar.value
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(controller.isPickingAvatar.value ? '正在打开相册…' : '从相册选择'),
          ),
        ),*/
        const SizedBox(height: AppSizes.paddingXl),
        Obx(
          () => RegisterTextField(
            controller: controller.nicknameController,
            focusNode: controller.nicknameFocusNode,
            hint: '昵称',
            icon: Icons.face_outlined,
            maxLength: 128,
            errorText: controller.nicknameError.value,
            textInputAction: controller.needsInvite
                ? TextInputAction.next
                : TextInputAction.done,
            onChanged: (_) => controller.nicknameError.value = null,
          ),
        ),
        if (controller.needsInvite) ...[
          const SizedBox(height: AppSizes.paddingLg),
          Obx(
            () => RegisterTextField(
              controller: controller.inviteController,
              focusNode: controller.inviteFocusNode,
              hint: '邀请码（邀请人的用户名）',
              icon: Icons.card_giftcard_outlined,
              errorText: controller.inviteError.value,
              textInputAction: TextInputAction.done,
              onChanged: (_) => controller.inviteError.value = null,
            ),
          ),
        ],
        const SizedBox(height: AppSizes.paddingLg),
        Obx(
          () => _AgreementRow(
            checked: controller.acceptedAgreement.value,
            errorText: controller.agreementError.value,
            onToggle: controller.toggleAgreement,
            onAgreement: controller.openServiceAgreement,
            onPrivacy: controller.openPrivacyPolicy,
          ),
        ),
        const SizedBox(height: AppSizes.paddingLg),
        Obx(
          () => AuthPrimaryButton(
            label: '完成注册',
            onPressed: controller.register,
            loading: controller.isSubmitting.value,
            showTrailingIcon: false,
          ),
        ),
      ],
    );
  }
}

class _SelectedAvatar extends StatelessWidget {
  const _SelectedAvatar({
    required this.localAvatar,
    required this.defaultAvatarPath,
    required this.onTap,
  });

  final AvatarUploadFile? localAvatar;
  final String defaultAvatarPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 112,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: localAvatar == null
                  ? Image.asset(
                      defaultAvatarPath,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                    )
                  : Image.memory(
                      localAvatar!.bytes,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            Positioned(
              right: -2,
              bottom: 4,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.tokens.brand,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '已选择的默认头像' : '选择默认头像',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? context.tokens.brand
                  : context.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: ClipOval(child: Image.asset(path, fit: BoxFit.cover)),
        ),
      ),
    );
  }
}

/// 用户名检查状态直接显示在输入框尾部，避免成功提示改变表单纵向间距。
class _UsernameAvailabilityIcon extends StatelessWidget {
  const _UsernameAvailabilityIcon({required this.state});

  final UsernameAvailabilityState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      UsernameAvailabilityState.idle => const SizedBox.shrink(),
      UsernameAvailabilityState.checking => const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      UsernameAvailabilityState.available => Tooltip(
        message: '用户名可用',
        child: Icon(
          Icons.check_circle_rounded,
          color: context.tokens.online,
          size: 23,
        ),
      ),
      UsernameAvailabilityState.unavailable => Tooltip(
        message: '用户名已被使用',
        child: Icon(
          Icons.cancel_rounded,
          color: context.colorScheme.error,
          size: 23,
        ),
      ),
      UsernameAvailabilityState.failed => Tooltip(
        message: '暂时无法检查，将在提交时校验',
        child: Icon(
          Icons.error_outline_rounded,
          color: context.colorScheme.onSurfaceVariant,
          size: 22,
        ),
      ),
    };
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({
    required this.loading,
    required this.seconds,
    required this.onPressed,
  });

  final bool loading;
  final int seconds;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: loading || seconds > 0 ? null : onPressed,
      child: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(seconds > 0 ? '${seconds}s' : '获取验证码'),
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.checked,
    required this.errorText,
    required this.onToggle,
    required this.onAgreement,
    required this.onPrivacy,
  });

  final bool checked;
  final String? errorText;
  final VoidCallback onToggle;
  final VoidCallback onAgreement;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final normal = context.colorScheme.onSurfaceVariant;
    final link = context.tokens.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Checkbox(value: checked, onChanged: (_) => onToggle()),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text.rich(
                  TextSpan(
                    style: AppTextStyles.metadata.copyWith(color: normal),
                    children: [
                      const TextSpan(text: '我已阅读并同意 '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: onAgreement,
                          child: Text(
                            '《用户协议》',
                            style: AppTextStyles.metadata.copyWith(color: link),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' 和 '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: onPrivacy,
                          child: Text(
                            '《隐私政策》',
                            style: AppTextStyles.metadata.copyWith(color: link),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              errorText!,
              style: AppTextStyles.metadata.copyWith(
                color: context.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: AppTextStyles.navTitle.copyWith(
            color: context.colorScheme.onSurface,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: AppSizes.paddingSm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.messageBody.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LoginLink extends StatelessWidget {
  const _LoginLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '已有账号？',
          style: AppTextStyles.metadata.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            '立即登录',
            style: AppTextStyles.metadata.copyWith(
              color: context.tokens.brand,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
