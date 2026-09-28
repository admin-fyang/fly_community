/// 社区版“我的”页只管理账号资料与设置入口。
library;

import 'package:get/get.dart';
import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import '../../core/session/session_controller.dart';
import '../../data/models/profile_detail_model.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_repository.dart';
import '../../routes/app_routes.dart';

class MineController extends GetxController with PageReadTracking {
  MineController({UserRepository? repository, SessionController? sessionController})
      : _repository = repository ?? Get.find<UserRepository>(),
        _sessionController = sessionController ?? Get.find<SessionController>();

  final UserRepository _repository;
  final SessionController _sessionController;
  final profile = Rxn<UserProfile>();
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  ProfileDetailModel get heroDetail {
    final value = profile.value;
    final session = _sessionController.currentUser.value;
    final username = session?.username ?? value?.username ?? '';
    final name = (session?.name ?? value?.name ?? '').trim();
    return ProfileDetailModel(
      id: value?.id ?? session?.id ?? '',
      publicId: value?.publicId ?? session?.publicId ?? '',
      name: name.isEmpty ? '用户' : name,
      avatarUrl: session?.avatarUrl ?? value?.avatarUrl,
      presence: username.trim().isEmpty ? '未设置' : username.trim(),
      username: username,
      verified: session?.verified ?? value?.verified ?? false,
    );
  }

  Future<void> load() async {
    if (isLoading.value) return;
    isLoading.value = true;
    errorMessage.value = '';
    final finishPageRead = pageReads.begin('profile');
    try {
      final latest = await _repository.getCurrentUser();
      profile.value = latest;
      await _sessionController.updateFromProfile(latest);
    } catch (_) {
      errorMessage.value = '个人资料加载失败，点击重试';
    } finally {
      finishPageRead();
      isLoading.value = false;
    }
  }

  Future<void> openEditProfile() async {
    await Get.toNamed<void>(AppRoutes.editProfile);
    await load();
  }

  void openSettings() => Get.toNamed(AppRoutes.settings);
}
