/// 账号安全仓储边界。
library;

import '../entities/account_security_result.dart';

abstract interface class AccountSecurityRepository {
  /// 修改当前密码；当前会话保留，其他设备会话由服务端撤销。
  Future<SessionRevocationResult> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// 提交全局唯一的账号注销申请。
  Future<AccountDeletionResult> requestDeletion({
    required String currentPassword,
  });

  /// 取消当前账号唯一的待生效注销申请，因此无需客户端持有申请 ID。
  Future<AccountDeletionResult> cancelDeletion();
}
