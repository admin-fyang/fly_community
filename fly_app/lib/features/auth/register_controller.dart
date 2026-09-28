/// 注册流程控制器。
///
/// 统一管理账号、联系方式验证和资料完善三类状态。页面只渲染当前步骤并转发
/// 用户事件，注册请求、配置切换、头像选择和错误定位均留在 Controller。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../data/services/im_lifecycle_service.dart';
import '../../data/services/public_link_service.dart';
import '../../data/services/system_time_service.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/entities/registration_request.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/services/avatar_picker_service.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/region_code_picker.dart';
import '../notifications/notification_unread_controller.dart';

enum RegistrationStep { account, verification, profile }

enum RegistrationContactChannel { phone, email }

enum UsernameAvailabilityState {
  idle,
  checking,
  available,
  unavailable,
  failed,
}

class RegisterController extends GetxController {
  RegisterController({
    AuthRepository? repository,
    UserRepository? userRepository,
    SessionController? sessionController,
    AvatarPickerService? avatarPicker,
    PublicLinkService? publicLinkService,
  }) : _repository = repository ?? Get.find<AuthRepository>(),
       _userRepository = userRepository ?? Get.find<UserRepository>(),
       _sessionController = sessionController ?? Get.find<SessionController>(),
       _avatarPicker = avatarPicker ?? Get.find<AvatarPickerService>(),
       _publicLinkService = publicLinkService;

  /// 顺序显式固定，避免 UUID 文件名排序变化造成默认头像漂移。
  static const defaultAvatarPaths = <String>[
    'assets/image/avatar/5cdffdc0-b8d6-460d-a237-070736d8dcfb.webp',
    'assets/image/avatar/37a256aa-eaa8-4308-bc39-1777cfe252e8.webp',
    'assets/image/avatar/71d5d7ba-d002-48e2-a73a-e2e027b201fc.webp',
    'assets/image/avatar/ba7acf96-acb5-4301-92a9-bf540f717b14.webp',
    'assets/image/avatar/c6d19905-21ab-4072-b955-b5df7756f55e.webp',
    'assets/image/avatar/8c8cc971-ed30-4461-a331-cc64319e9e53.webp',
    'assets/image/avatar/8f33949b-6c44-4746-9406-0e7d74f1542b.webp',
    'assets/image/avatar/a11cc621-7c59-457c-a9bd-78f925f03b4e.webp',
    'assets/image/avatar/bada55f4-0062-4f74-9baa-dd9c9fe7d200.webp',
    'assets/image/avatar/c8de2f84-ca02-4cff-b994-1f31fba0ebae.webp',
    'assets/image/avatar/d40df0e0-efbd-4a6d-9b3e-e452f70af7e8.webp',
    'assets/image/avatar/f2f7d5b9-963b-4888-b79c-350c3c40cb5e.webp',
    'assets/image/avatar/f51af4f4-1217-45bf-b932-249a9f32e786.webp',
  ];

  final AuthRepository _repository;
  final UserRepository _userRepository;
  final SessionController _sessionController;
  final AvatarPickerService _avatarPicker;
  final PublicLinkService? _publicLinkService;
  final SystemTimeService _systemConfig = Get.find<SystemTimeService>();

  final currentStep = RegistrationStep.account.obs;
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();
  final phoneCodeController = TextEditingController();
  final emailController = TextEditingController();
  final emailCodeController = TextEditingController();
  final nicknameController = TextEditingController();
  final inviteController = TextEditingController();

  final usernameFocusNode = FocusNode();
  final phoneFocusNode = FocusNode();
  final phoneCodeFocusNode = FocusNode();
  final emailFocusNode = FocusNode();
  final emailCodeFocusNode = FocusNode();
  final nicknameFocusNode = FocusNode();
  final inviteFocusNode = FocusNode();

  final usernameError = RxnString();
  final passwordError = RxnString();
  final confirmPasswordError = RxnString();
  final phoneError = RxnString();
  final phoneCodeError = RxnString();
  final emailError = RxnString();
  final emailCodeError = RxnString();
  final nicknameError = RxnString();
  final inviteError = RxnString();
  final agreementError = RxnString();

  final usernameAvailability = UsernameAvailabilityState.idle.obs;
  final isSendingPhoneCode = false.obs;
  final isSendingEmailCode = false.obs;
  final phoneResendSeconds = 0.obs;
  final emailResendSeconds = 0.obs;
  final phoneVerificationRequestId = RxnString();
  final emailVerificationRequestId = RxnString();
  final regionCode = 'CN'.obs;
  final acceptedAgreement = false.obs;
  final isPickingAvatar = false.obs;
  final isSubmitting = false.obs;
  final selectedAvatarPath = defaultAvatarPaths.first.obs;
  final selectedLocalAvatar = Rxn<AvatarUploadFile>();

  Timer? _phoneTimer;
  Timer? _emailTimer;
  Timer? _usernameDebounce;
  Worker? _configWorker;
  int _usernameCheckGeneration = 0;

  bool get needsPhoneVerification {
    _systemConfig.revision.value;
    return _systemConfig.registrationNeedsPhoneVerification;
  }

  bool get needsEmailVerification {
    _systemConfig.revision.value;
    return _systemConfig.registrationNeedsEmailVerification;
  }

  bool get needsVerification =>
      needsPhoneVerification || needsEmailVerification;

  bool get needsInvite {
    _systemConfig.revision.value;
    return _systemConfig.registrationNeedsInvite;
  }

  List<RegistrationStep> get visibleSteps => <RegistrationStep>[
    RegistrationStep.account,
    if (needsVerification) RegistrationStep.verification,
    RegistrationStep.profile,
  ];

  int get currentStepIndex => visibleSteps.indexOf(currentStep.value);

  String get usernameAvailabilityMessage =>
      switch (usernameAvailability.value) {
        UsernameAvailabilityState.checking => '正在检查用户名…',
        UsernameAvailabilityState.available => '用户名可用',
        UsernameAvailabilityState.unavailable => '用户名已被使用',
        UsernameAvailabilityState.failed => '暂时无法检查，将在提交时校验',
        UsernameAvailabilityState.idle => '',
      };

  @override
  void onInit() {
    super.onInit();
    usernameFocusNode.addListener(_handleUsernameFocus);
    _applyConfig();
    _configWorker = ever<int>(_systemConfig.revision, (_) => _applyConfig());
  }

  void _handleUsernameFocus() {
    if (!usernameFocusNode.hasFocus) {
      _usernameDebounce?.cancel();
      unawaited(checkUsernameAvailability());
    }
  }

  /// 原子配置刷新后统一调整流程，避免页面保留已经关闭的验证参数。
  void _applyConfig() {
    if (!_systemConfig.canRegister) {
      _stopAllCountdowns();
      isSubmitting.value = false;
      if (_isRegistrationRoute(Get.currentRoute)) {
        Get.offNamed(AppRoutes.login);
        AppToast.warning('注册功能已关闭');
      }
      return;
    }

    if (!needsPhoneVerification) _clearPhoneVerification();
    if (!needsEmailVerification) _clearEmailVerification();

    if (!needsVerification &&
        currentStep.value == RegistrationStep.verification) {
      currentStep.value = RegistrationStep.profile;
    } else if (currentStep.value == RegistrationStep.profile &&
        needsVerification &&
        !_enabledVerificationComplete) {
      currentStep.value = RegistrationStep.verification;
      AppToast.info('注册验证配置已更新，请先完成验证');
    }
  }

  bool _isRegistrationRoute(String route) =>
      route == AppRoutes.register ||
      route == AppRoutes.registerPhone ||
      route == AppRoutes.registerEmail;

  /// 格式通过后查询；网络失败不阻断，唯一冲突仍由注册接口兜底。
  Future<void> checkUsernameAvailability() async {
    final username = usernameController.text.trim();
    final validation = _validateUsername(username);
    if (validation != null) {
      usernameAvailability.value = UsernameAvailabilityState.idle;
      return;
    }
    final generation = ++_usernameCheckGeneration;
    usernameAvailability.value = UsernameAvailabilityState.checking;
    try {
      final available = await _repository.isUsernameAvailable(username);
      if (generation != _usernameCheckGeneration ||
          usernameController.text.trim() != username) {
        return;
      }
      usernameAvailability.value = available
          ? UsernameAvailabilityState.available
          : UsernameAvailabilityState.unavailable;
      usernameError.value = available ? null : '用户名已被使用';
    } catch (_) {
      if (generation == _usernameCheckGeneration) {
        usernameAvailability.value = UsernameAvailabilityState.failed;
      }
    }
  }

  void onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    _usernameCheckGeneration++;
    usernameAvailability.value = UsernameAvailabilityState.idle;
    usernameError.value = null;
    if (_validateUsername(value.trim()) == null) {
      // 输入稳定 500ms 视为本轮输入完成，减少逐字符产生的无效请求。
      _usernameDebounce = Timer(
        const Duration(milliseconds: 500),
        () => unawaited(checkUsernameAvailability()),
      );
    }
  }

  Future<void> nextFromAccount() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validateAccountStep()) return;
    if (usernameAvailability.value == UsernameAvailabilityState.idle ||
        usernameAvailability.value == UsernameAvailabilityState.checking) {
      await checkUsernameAvailability();
    }
    if (usernameAvailability.value == UsernameAvailabilityState.unavailable) {
      usernameFocusNode.requestFocus();
      return;
    }
    currentStep.value = needsVerification
        ? RegistrationStep.verification
        : RegistrationStep.profile;
  }

  void nextFromVerification() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_validateVerificationStep()) {
      currentStep.value = RegistrationStep.profile;
    }
  }

  void previousStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    switch (currentStep.value) {
      case RegistrationStep.profile:
        currentStep.value = needsVerification
            ? RegistrationStep.verification
            : RegistrationStep.account;
        return;
      case RegistrationStep.verification:
        currentStep.value = RegistrationStep.account;
        return;
      case RegistrationStep.account:
        Get.offNamed(AppRoutes.login);
        return;
    }
  }

  bool _validateAccountStep() {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    usernameError.value = _validateUsername(username);
    passwordError.value = _validatePassword(password);
    confirmPasswordError.value = confirmPasswordController.text != password
        ? '两次输入的密码不一致'
        : null;
    if (usernameError.value != null) {
      usernameFocusNode.requestFocus();
      return false;
    }
    return passwordError.value == null && confirmPasswordError.value == null;
  }

  String? _validateUsername(String value) {
    if (value.isEmpty) return '请输入用户名';
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$').hasMatch(value)) {
      return '用户名需为 5–32 位，并以字母开头，仅含字母、数字和下划线';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.length < 8 || value.length > 64) return '密码长度需为 8–64 位';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return '密码必须同时包含字母和数字';
    }
    return null;
  }

  Future<void> sendCode(RegistrationContactChannel channel) async {
    final isPhone = channel == RegistrationContactChannel.phone;
    if ((isPhone && !needsPhoneVerification) ||
        (!isPhone && !needsEmailVerification)) {
      return;
    }
    if (isPhone ? isSendingPhoneCode.value : isSendingEmailCode.value) return;
    if (isPhone ? phoneResendSeconds.value > 0 : emailResendSeconds.value > 0) {
      return;
    }

    final target = isPhone
        ? phoneController.text.trim()
        : emailController.text.trim();
    final validation = isPhone
        ? _validatePhone(target)
        : _validateEmail(target);
    if (isPhone) {
      phoneError.value = validation;
      if (validation != null) phoneFocusNode.requestFocus();
      isSendingPhoneCode.value = validation == null;
    } else {
      emailError.value = validation;
      if (validation != null) emailFocusNode.requestFocus();
      isSendingEmailCode.value = validation == null;
    }
    if (validation != null) return;

    try {
      final option = RegionCodeOption.byCode(regionCode.value);
      final challenge = await _repository.requestVerificationCode(
        channel: isPhone ? 'phone' : 'email',
        target: target,
        regionCode: isPhone ? regionCode.value : null,
        countryCode: isPhone ? option.dialCode : null,
      );
      if (isPhone) {
        phoneVerificationRequestId.value = challenge.requestId;
        if (challenge.developmentCode != null) {
          phoneCodeController.text = challenge.developmentCode!;
        }
      } else {
        emailVerificationRequestId.value = challenge.requestId;
        if (challenge.developmentCode != null) {
          emailCodeController.text = challenge.developmentCode!;
        }
      }
      _startCountdown(channel, challenge.resendIn);
      AppToast.success('验证码已发送至 ${challenge.targetMasked}');
    } on ApiException catch (error) {
      AppToast.error(error.message);
    } catch (_) {
      AppToast.error('验证码发送失败，请稍后重试');
    } finally {
      if (isPhone) {
        isSendingPhoneCode.value = false;
      } else {
        isSendingEmailCode.value = false;
      }
    }
  }

  void onPhoneChanged(String _) {
    phoneError.value = null;
    phoneCodeError.value = null;
    phoneVerificationRequestId.value = null;
    phoneCodeController.clear();
    _stopCountdown(RegistrationContactChannel.phone);
  }

  void onEmailChanged(String _) {
    emailError.value = null;
    emailCodeError.value = null;
    emailVerificationRequestId.value = null;
    emailCodeController.clear();
    _stopCountdown(RegistrationContactChannel.email);
  }

  void setRegionCode(String value) {
    if (regionCode.value == value) return;
    regionCode.value = value;
    onPhoneChanged(phoneController.text);
  }

  bool _validateVerificationStep() {
    if (needsPhoneVerification) {
      phoneError.value = _validatePhone(phoneController.text.trim());
      phoneCodeError.value = phoneVerificationRequestId.value == null
          ? '请先获取短信验证码'
          : !_validCode(phoneCodeController.text.trim())
          ? '请输入 6 位短信验证码'
          : null;
      if (phoneError.value != null || phoneCodeError.value != null) {
        (phoneError.value != null ? phoneFocusNode : phoneCodeFocusNode)
            .requestFocus();
        return false;
      }
    }
    if (needsEmailVerification) {
      emailError.value = _validateEmail(emailController.text.trim());
      emailCodeError.value = emailVerificationRequestId.value == null
          ? '请先获取邮箱验证码'
          : !_validCode(emailCodeController.text.trim())
          ? '请输入 6 位邮箱验证码'
          : null;
      if (emailError.value != null || emailCodeError.value != null) {
        (emailError.value != null ? emailFocusNode : emailCodeFocusNode)
            .requestFocus();
        return false;
      }
    }
    return true;
  }

  String? _validatePhone(String value) =>
      RegExp(r'^\d[\d\s-]{5,}$').hasMatch(value) ? null : '请输入有效手机号';

  String? _validateEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : '请输入有效邮箱';

  bool _validCode(String value) => RegExp(r'^\d{6}$').hasMatch(value);

  bool get _enabledVerificationComplete =>
      (!needsPhoneVerification ||
          (phoneVerificationRequestId.value != null &&
              _validCode(phoneCodeController.text.trim()))) &&
      (!needsEmailVerification ||
          (emailVerificationRequestId.value != null &&
              _validCode(emailCodeController.text.trim())));

  void selectDefaultAvatar(String path) {
    if (!defaultAvatarPaths.contains(path)) return;
    selectedAvatarPath.value = path;
    selectedLocalAvatar.value = null;
  }

  Future<void> pickAvatarFromGallery() async {
    if (isPickingAvatar.value || isSubmitting.value) return;
    isPickingAvatar.value = true;
    try {
      final selected = await _avatarPicker.pick(AvatarPickSource.gallery);
      if (selected != null) selectedLocalAvatar.value = selected;
    } on ApiException catch (error) {
      AppToast.error(error.message);
    } catch (_) {
      AppToast.error('头像选择失败，请重试');
    } finally {
      isPickingAvatar.value = false;
    }
  }

  void toggleAgreement() {
    acceptedAgreement.toggle();
    if (acceptedAgreement.value) agreementError.value = null;
  }

  Future<void> register() async {
    if (isSubmitting.value) return;
    if (!_systemConfig.canRegister) {
      _applyConfig();
      return;
    }
    if (!_validateAccountStep()) {
      currentStep.value = RegistrationStep.account;
      return;
    }
    if (needsVerification && !_validateVerificationStep()) {
      currentStep.value = RegistrationStep.verification;
      return;
    }
    final nickname = nicknameController.text.trim();
    nicknameError.value = nickname.isEmpty
        ? '请输入昵称'
        : nickname.length > 128
        ? '昵称不能超过 128 个字符'
        : null;
    final inviteCode = _normalizedInviteCode;
    inviteError.value = needsInvite && inviteCode == null ? '请输入邀请码' : null;
    agreementError.value = acceptedAgreement.value ? null : '请阅读并同意用户协议和隐私政策';
    if (nicknameError.value != null) {
      nicknameFocusNode.requestFocus();
      return;
    }
    if (inviteError.value != null) {
      inviteFocusNode.requestFocus();
      return;
    }
    if (agreementError.value != null) return;

    isSubmitting.value = true;
    try {
      final option = RegionCodeOption.byCode(regionCode.value);
      final session = await _repository.register(
        RegistrationRequest(
          username: usernameController.text.trim(),
          nickname: nickname,
          password: passwordController.text,
          inviteCode: needsInvite ? inviteCode : null,
          phoneVerification: needsPhoneVerification
              ? RegistrationVerification(
                  target: phoneController.text.trim(),
                  countryCode: option.dialCode,
                  verificationRequestId: phoneVerificationRequestId.value!,
                  code: phoneCodeController.text.trim(),
                )
              : null,
          emailVerification: needsEmailVerification
              ? RegistrationVerification(
                  target: emailController.text.trim(),
                  verificationRequestId: emailVerificationRequestId.value!,
                  code: emailCodeController.text.trim(),
                )
              : null,
        ),
      );
      _sessionController.acceptSession(session);
      Get.offAllNamed(AppRoutes.conversations);
      AppToast.success('注册成功');
      unawaited(_uploadSelectedAvatar());
      unawaited(Get.find<NotificationUnreadController>().refreshCount());
      unawaited(_activateImAfterRegistration());
    } on ApiException catch (error) {
      await _handleRegisterError(error);
    } catch (_) {
      AppToast.error('注册失败，请稍后重试');
    } finally {
      isSubmitting.value = false;
    }
  }

  String? get _normalizedInviteCode {
    final value = inviteController.text.trim().replaceFirst(RegExp(r'^@'), '');
    return value.isEmpty ? null : value;
  }

  Future<void> _handleRegisterError(ApiException error) async {
    switch (error.code) {
      case 'REGISTER_DISABLED':
        await _systemConfig.refresh(force: true);
        _applyConfig();
        return;
      case 'REGISTER_VERIFICATION_DISABLED':
        await _systemConfig.refresh(force: true);
        _applyConfig();
        AppToast.warning(error.message);
        return;
      case 'REGISTER_VERIFICATION_REQUIRED':
        currentStep.value = RegistrationStep.verification;
        _validateVerificationStep();
        AppToast.error('请完成注册验证');
        return;
      case 'USERNAME_ALREADY_USED':
        currentStep.value = RegistrationStep.account;
        usernameAvailability.value = UsernameAvailabilityState.unavailable;
        usernameError.value = '用户名已被使用';
        usernameFocusNode.requestFocus();
        AppToast.error('用户名已被使用');
        return;
      case 'INVITE_CODE_REQUIRED':
        currentStep.value = RegistrationStep.profile;
        inviteError.value = '请输入邀请码';
        inviteFocusNode.requestFocus();
        AppToast.error('请输入邀请码');
        return;
      case 'INVITE_CODE_INVALID':
        currentStep.value = RegistrationStep.profile;
        inviteError.value = '邀请码无效';
        inviteFocusNode.requestFocus();
        AppToast.error('邀请码无效');
        return;
      default:
        AppToast.error(error.message);
        return;
    }
  }

  /// Token 建立后复用现有凭证、对象直传、完成确认和绑定链路。
  Future<void> _uploadSelectedAvatar() async {
    try {
      final selected = selectedLocalAvatar.value ?? await _loadDefaultAvatar();
      final profile = await _userRepository.uploadAvatar(selected);
      await _sessionController.updateFromProfile(profile);
      AppToast.success('头像已设置');
    } catch (_) {
      AppToast.warning('注册成功，但头像上传失败，可在我的资料中重试');
    }
  }

  Future<AvatarUploadFile> _loadDefaultAvatar() async {
    final path = selectedAvatarPath.value;
    final data = await rootBundle.load(path);
    return AvatarUploadFile(
      filename: path.split('/').last,
      mimeType: 'image/png',
      bytes: Uint8List.sublistView(data),
    );
  }

  Future<void> _activateImAfterRegistration() async {
    final result = await Get.find<ImLifecycleService>().activateSession();
    if (result.shouldWarnSync) {
      AppToast.warning('注册成功，消息同步暂时失败，将自动重试');
    }
  }

  Future<void> openServiceAgreement() =>
      _openPublicLink(PublicLinkType.userAgreement, '用户协议');

  Future<void> openPrivacyPolicy() =>
      _openPublicLink(PublicLinkType.privacyPolicy, '隐私政策');

  Future<void> _openPublicLink(PublicLinkType type, String label) async {
    final service = _publicLinkService ?? Get.find<PublicLinkService>();
    final result = await service.open(type);
    if (result == PublicLinkOpenResult.opened) return;
    AppToast.error(
      result == PublicLinkOpenResult.notConfigured
          ? '$label地址尚未配置'
          : '$label打开失败，请稍后重试',
    );
  }

  void _startCountdown(RegistrationContactChannel channel, int seconds) {
    _stopCountdown(channel);
    final target = channel == RegistrationContactChannel.phone
        ? phoneResendSeconds
        : emailResendSeconds;
    target.value = seconds;
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (target.value <= 1) {
        _stopCountdown(channel);
      } else {
        target.value--;
      }
    });
    if (channel == RegistrationContactChannel.phone) {
      _phoneTimer = timer;
    } else {
      _emailTimer = timer;
    }
  }

  void _stopCountdown(RegistrationContactChannel channel) {
    if (channel == RegistrationContactChannel.phone) {
      _phoneTimer?.cancel();
      _phoneTimer = null;
      phoneResendSeconds.value = 0;
    } else {
      _emailTimer?.cancel();
      _emailTimer = null;
      emailResendSeconds.value = 0;
    }
  }

  void _clearPhoneVerification() {
    phoneController.clear();
    phoneCodeController.clear();
    phoneVerificationRequestId.value = null;
    phoneError.value = null;
    phoneCodeError.value = null;
    _stopCountdown(RegistrationContactChannel.phone);
  }

  void _clearEmailVerification() {
    emailController.clear();
    emailCodeController.clear();
    emailVerificationRequestId.value = null;
    emailError.value = null;
    emailCodeError.value = null;
    _stopCountdown(RegistrationContactChannel.email);
  }

  void _stopAllCountdowns() {
    _stopCountdown(RegistrationContactChannel.phone);
    _stopCountdown(RegistrationContactChannel.email);
  }

  @override
  void onClose() {
    _usernameDebounce?.cancel();
    _stopAllCountdowns();
    _configWorker?.dispose();
    usernameFocusNode.removeListener(_handleUsernameFocus);
    for (final controller in <TextEditingController>[
      usernameController,
      passwordController,
      confirmPasswordController,
      phoneController,
      phoneCodeController,
      emailController,
      emailCodeController,
      nicknameController,
      inviteController,
    ]) {
      controller.dispose();
    }
    for (final node in <FocusNode>[
      usernameFocusNode,
      phoneFocusNode,
      phoneCodeFocusNode,
      emailFocusNode,
      emailCodeFocusNode,
      nicknameFocusNode,
      inviteFocusNode,
    ]) {
      node.dispose();
    }
    super.onClose();
  }
}
