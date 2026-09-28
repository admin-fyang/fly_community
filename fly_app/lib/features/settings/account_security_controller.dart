/// 账号安全入口控制器。
///
/// 管理取消注销申请的提交状态；修改密码和申请注销分别由独立表单控制器负责。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../domain/repositories/account_security_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../domain/entities/account_security_result.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_dialog.dart';

class AccountSecurityController extends GetxController with PageReadTracking {
  AccountSecurityController({
    AccountSecurityRepository? repository,
    UserRepository? userRepository,
  }) : _repository = repository ?? Get.find<AccountSecurityRepository>(),
       _userRepository = userRepository ?? Get.find<UserRepository>();

  final AccountSecurityRepository _repository;
  final UserRepository _userRepository;
  final isCancellingDeletion = false.obs;
  final isCheckingDeletion = true.obs;
  final hasPendingDeletion = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadDeletionStatus();
  }

  void openChangePassword() => Get.toNamed(AppRoutes.changePassword);

  Future<void> openDeleteAccount() async {
    final result = await Get.toNamed<AccountDeletionResult>(
      AppRoutes.deleteAccount,
    );
    if (result != null) {
      hasPendingDeletion.value = true;
    }
  }

  /// 取消入口只能由服务端当前资料证明，网络失败时绝不使用本地猜测。
  Future<void> _loadDeletionStatus() async {
    final finishPageRead = pageReads.begin('_loadDeletionStatus');
    try {
      isCheckingDeletion.value = true;
      hasPendingDeletion.value = false;
      try {
        final profile = await _userRepository.getCurrentUser();
        hasPendingDeletion.value = profile.status == 30;
      } on ApiException catch (error) {
        pageReads.reportError(error.message);
      } catch (_) {
        pageReads.reportError('注销状态查询失败，请稍后重试');
      } finally {
        isCheckingDeletion.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  Future<void> cancelDeletion() async {
    if (isCancellingDeletion.value) return;
    final confirmed = await AppConfirmDialog.show(
      title: '取消账号注销',
      message: '确认保留当前账号并取消待生效的注销申请吗？',
      confirmText: '确认取消注销',
    );
    if (confirmed != true) return;

    isCancellingDeletion.value = true;
    try {
      await _repository.cancelDeletion();
      hasPendingDeletion.value = false;
      AppToast.success('注销申请已取消，账号可继续正常使用');
    } on ApiException catch (error) {
      AppToast.error(error.message);
    } catch (_) {
      AppToast.error('取消注销失败，请稍后重试');
    } finally {
      isCancellingDeletion.value = false;
    }
  }
}
