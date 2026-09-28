/// 账号安全仓储实现。
library;

import '../../core/network/api_client.dart';
import '../../core/network/api_paths.dart';
import '../../domain/entities/account_security_result.dart';
import '../../domain/repositories/account_security_repository.dart';

class AccountSecurityRepositoryImpl implements AccountSecurityRepository {
  const AccountSecurityRepositoryImpl(this._client);

  final ApiClient _client;

  @override
  Future<SessionRevocationResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _client.patch<SessionRevocationResult>(
      ApiPaths.currentUserPassword,
      data: {'current_password': currentPassword, 'new_password': newPassword},
      decoder: (data) => SessionRevocationResult.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<AccountDeletionResult> requestDeletion({
    required String currentPassword,
  }) {
    return _client.post<AccountDeletionResult>(
      ApiPaths.accountDeletionRequests,
      data: {'current_password': currentPassword},
      decoder: (data) => AccountDeletionResult.fromJson(_jsonObject(data)),
    );
  }

  @override
  Future<AccountDeletionResult> cancelDeletion() {
    return _client.post<AccountDeletionResult>(
      ApiPaths.cancelAccountDeletion,
      decoder: (data) => AccountDeletionResult.fromJson(_jsonObject(data)),
    );
  }
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw const FormatException('data 必须为 JSON 对象');
}
