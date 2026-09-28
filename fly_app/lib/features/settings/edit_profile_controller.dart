/// 编辑个人资料页控制器。
///
/// 负责读取、校验和提交当前用户资料，并处理 profile_version 乐观锁冲突。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_sizes.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_repository.dart';
import '../../shared/services/avatar_picker_service.dart';
import '../../shared/utils/app_toast.dart';

class EditProfileController extends GetxController with PageReadTracking {
  EditProfileController({
    UserRepository? repository,
    SessionController? sessionController,
    AvatarPickerService? avatarPicker,
  }) : _repository = repository ?? Get.find<UserRepository>(),
       _sessionController = sessionController ?? Get.find<SessionController>(),
       _avatarPicker = avatarPicker ?? Get.find<AvatarPickerService>();

  final UserRepository _repository;
  final SessionController _sessionController;
  final AvatarPickerService _avatarPicker;

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final usernameController = TextEditingController();
  final bioController = TextEditingController();

  final profile = Rxn<UserProfile>();
  final usernameAvailable = true.obs;
  final birthday = Rxn<DateTime>();
  final regionCode = 'CN'.obs;
  final birthdayVisibility = 20.obs;
  final phoneVisibility = 20.obs;
  final lastSeenVisibility = 20.obs;
  final isLoading = false.obs;
  final isSaving = false.obs;
  final isUploadingAvatar = false.obs;
  final avatarUploadProgress = 0.0.obs;
  final localAvatarBytes = Rxn<Uint8List>();

  @override
  void onInit() {
    super.onInit();
    _applySessionFallback();
    load();
  }

  Future<void> load() async {
    final finishPageRead = pageReads.begin('load');
    try {
      if (isLoading.value) return;
      isLoading.value = true;
      try {
        _applyProfile(await _repository.getCurrentUser());
      } on ApiException catch (error) {
        AppToast.show(error.message);
      } catch (_) {
        AppToast.show('用户资料加载失败');
      } finally {
        isLoading.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  void validateUsername(String value) {
    usernameAvailable.value = RegExp(
      r'^[A-Za-z][A-Za-z0-9_]{4,31}$',
    ).hasMatch(value.trim());
  }

  String get displayName {
    final value = profile.value?.name ?? firstNameController.text.trim();
    return value.isEmpty ? '用户' : value;
  }

  String? get avatarUrl => profile.value?.avatarUrl;

  String get phoneText {
    final value = profile.value?.phone;
    if (value == null || value.isEmpty) return '未绑定手机号';
    // 页面已单独展示地区号，手机号正文去掉常见国际区号前缀，避免显示成“+86 +86 138...”
    return value.replaceFirst(RegExp(r'^\+\d{1,4}\s*'), '');
  }

  bool get phoneVerified => profile.value?.phoneVerified ?? false;

  String get birthdayText {
    final value = birthday.value;
    if (value == null) return '未设置';
    return '${value.year}年${value.month}月${value.day}日';
  }

  String get birthdayVisibilityLabel => switch (birthdayVisibility.value) {
    10 => '所有人',
    30 => '仅自己',
    _ => '仅限联系人',
  };

  void updateBirthday(DateTime value) {
    birthday.value = value;
  }

  void setRegionCode(String value) {
    regionCode.value = value;
  }

  Future<void> pickAndUploadAvatar(AvatarPickSource source) async {
    if (isUploadingAvatar.value || isSaving.value) return;
    if (profile.value == null) {
      AppToast.show('用户资料尚未加载完成');
      return;
    }

    try {
      final selected = await _avatarPicker.pick(source);
      if (selected == null) return;

      final previousPreview = localAvatarBytes.value;
      localAvatarBytes.value = selected.bytes;
      avatarUploadProgress.value = 0;
      isUploadingAvatar.value = true;
      try {
        final updated = await _repository.uploadAvatar(
          selected,
          onProgress: (sent, total) {
            if (total > 0) {
              avatarUploadProgress.value = (sent / total).clamp(0, 1);
            }
          },
        );

        // 头像绑定会递增 profile_version。这里只替换服务端快照，
        // 不调用 _applyProfile，避免覆盖用户尚未保存的文字表单。
        profile.value = updated;
        avatarUploadProgress.value = 1;
        await _sessionController.updateFromProfile(updated);
        AppToast.show('头像已更新');
      } on ApiException catch (error) {
        localAvatarBytes.value = previousPreview;
        AppToast.show(error.message);
      } catch (_) {
        localAvatarBytes.value = previousPreview;
        AppToast.show('头像上传失败，请重试');
      } finally {
        isUploadingAvatar.value = false;
      }
    } on ApiException catch (error) {
      AppToast.show(error.message);
    } catch (_) {
      AppToast.show('头像选择失败，请重试');
    }
  }

  Future<void> save() async {
    if (isSaving.value || isUploadingAvatar.value) return;
    final current = profile.value;
    if (current == null) {
      AppToast.show('用户资料尚未加载完成');
      return;
    }
    if (firstNameController.text.trim().isEmpty) {
      AppToast.show('名字不能为空');
      return;
    }
    if (!usernameAvailable.value) {
      AppToast.show('用户名格式不正确');
      return;
    }

    isSaving.value = true;
    try {
      final updated = await _repository.updateCurrentUser(
        profileVersion: current.profileVersion,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        username: usernameController.text.trim(),
        bio: bioController.text.trim(),
        birthday: birthday.value,
        regionCode: regionCode.value,
        birthdayVisibility: birthdayVisibility.value,
        phoneVisibility: phoneVisibility.value,
        lastSeenVisibility: lastSeenVisibility.value,
      );
      _applyProfile(updated);
      await _sessionController.updateFromProfile(updated);
      Get.back();
      AppToast.show('资料已保存');
    } on ApiException catch (error) {
      if (error.code == 'PROFILE_VERSION_CONFLICT') {
        await load();
        AppToast.show('资料已在其他设备更新，请确认后重新保存');
      } else {
        AppToast.show(error.message);
      }
    } catch (_) {
      AppToast.show('资料保存失败，请稍后重试');
    } finally {
      isSaving.value = false;
    }
  }

  void _applySessionFallback() {
    final user = _sessionController.currentUser.value;
    if (user == null) return;
    firstNameController.text = user.name;
    usernameController.text = (user.username ?? '').replaceFirst('@', '');
    validateUsername(usernameController.text);
  }

  void _applyProfile(UserProfile value) {
    profile.value = value;
    firstNameController.text = value.firstName.isEmpty
        ? value.name
        : value.firstName;
    lastNameController.text = value.lastName;
    usernameController.text = (value.username ?? '').replaceFirst('@', '');
    bioController.text = value.bio;
    birthday.value = value.birthday;
    regionCode.value = value.regionCode ?? 'CN';
    birthdayVisibility.value = value.birthdayVisibility;
    phoneVisibility.value = value.phoneVisibility;
    lastSeenVisibility.value = value.lastSeenVisibility;
    validateUsername(usernameController.text);
  }

  @override
  void onClose() {
    firstNameController.dispose();
    lastNameController.dispose();
    usernameController.dispose();
    bioController.dispose();
    super.onClose();
  }
}
