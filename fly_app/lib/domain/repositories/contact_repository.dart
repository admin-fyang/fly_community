library;

import '../../data/models/contact_model.dart';
import '../../data/models/paged_result.dart';
import '../../data/models/profile_detail_model.dart';

abstract interface class ContactRepository {
  Stream<List<ContactModel>> watchContacts();

  Future<void> refresh();

  /// 强制从服务端重建联系人目录快照。
  ///
  /// 与 [refresh] 的增量同步不同，本方法用于页面进入时主动取得最新目录，
  /// 成功结果必须先安全写入本地数据库，再由 [watchContacts] 驱动界面刷新。
  Future<void> refreshFromServer();

  Future<PagedResult<ContactModel>> getContactsPage({
    int limit = 50,
    String? cursor,
  });

  Future<List<ContactModel>> getContacts({int limit = 50, String? cursor});

  Future<List<ContactModel>> searchUsers({
    required String keyword,
    int limit = 20,
    String? countryCode,
  });

  Future<ProfileDetailModel> getUserProfile(String userId);

  Future<void> requestFriend({
    required String targetUserId,
    String remark = '',
  });

  Future<void> updateRemark({required String userId, required String remark});

  Future<void> updateSettings({
    required String userId,
    bool? isPinned,
    bool? isMuted,
  });

  Future<void> deleteContact(String userId);

  Future<void> blockUser(String userId);

  Future<void> unblockUser(String userId);
}
