/// 用户资料仓储接口。
library;

import '../entities/user_profile.dart';
import '../entities/avatar_upload.dart';

abstract interface class UserRepository {
  Future<UserProfile> getCurrentUser();

  Future<UserProfile> updateCurrentUser({
    required int profileVersion,
    required String firstName,
    required String lastName,
    required String username,
    required String bio,
    required DateTime? birthday,
    required String? regionCode,
    required int birthdayVisibility,
    required int phoneVisibility,
    required int lastSeenVisibility,
  });

  /// 完成头像凭证申请、对象直传、完成确认和资料绑定。
  Future<UserProfile> uploadAvatar(
    AvatarUploadFile file, {
    void Function(int sent, int total)? onProgress,
  });
}
