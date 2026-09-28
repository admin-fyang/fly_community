/// 联系人页控制器。
///
/// 提供按字母分组的联系人数据与索引定位。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import '../../core/utils/social_search.dart';

import 'dart:async';

import '../../core/network/network_recovery_controller.dart';

import 'package:get/get.dart';

import '../../data/enums/top_bar_mode.dart';
import '../../data/models/contact_model.dart';
import '../../core/utils/log_util.dart';
import '../../data/services/system_time_service.dart';
import '../../domain/repositories/contact_repository.dart';

/// 联系人分组：一个字母 + 该字母下的联系人
class ContactGroup {
  const ContactGroup(this.letter, this.items);
  final String letter;
  final List<ContactModel> items;
}

/// 联系人页状态
///
/// 只负责 UI 状态与 Mock 数据：顶栏搜索切换、关键词过滤、字母分组、索引高亮。
class ContactsController extends GetxController with PageReadTracking {
  ContactsController({SystemTimeService? systemConfig})
    : _systemConfig = systemConfig ?? Get.find<SystemTimeService>();

  final SystemTimeService _systemConfig;

  final topBarMode = TopBarMode.normal.obs;
  final keyword = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final hasMore = false.obs;

  /// 当前索引条高亮字母
  final activeLetter = ''.obs;

  final _all = <ContactModel>[].obs;
  StreamSubscription<List<ContactModel>>? _contactsSubscription;
  bool _refreshing = false;

  bool get canAddFriend {
    _systemConfig.revision.value;
    return _systemConfig.canAddFriend;
  }

  StreamSubscription<void>? _networkRecoverySubscription;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<NetworkRecoveryController>()) {
      _networkRecoverySubscription = Get.find<NetworkRecoveryController>()
          .recovered
          .listen((_) {
            if (!isClosed && errorMessage.value.isNotEmpty)
              unawaited(loadContacts(showActivity: false));
          });
    }
    _contactsSubscription = Get.find<ContactRepository>()
        .watchContacts()
        .listen((contacts) {
          if (isClosed) return;
          _all.assignAll(contacts);
          errorMessage.value = '';
        });
    unawaited(loadContacts());
  }

  @override
  void onClose() {
    _networkRecoverySubscription?.cancel();
    _contactsSubscription?.cancel();
    super.onClose();
  }

  Future<void> loadContacts({bool showActivity = true}) async {
    final finishPageRead = pageReads.begin('loadContacts', visible: showActivity);
    try {
      if (_refreshing || isClosed) return;
      _refreshing = true;
      isLoading.value = _all.isEmpty;
      errorMessage.value = '';
      try {
        // watchContacts 已先投影 SQLite 缓存；这里强制拉取带屏障水位的
        // 权威目录快照，成功后仍由数据库监听流统一刷新 UI。
        await Get.find<ContactRepository>().refreshFromServer();
        if (isClosed) return;
        errorMessage.value = '';
        hasMore.value = false;
      } catch (error) {
        if (isClosed) return;
        if (_all.isEmpty) {
          errorMessage.value = '联系人加载失败，请稍后重试';
        } else {
          LogUtil.d('后台刷新失败，继续显示本地联系人：$error', tag: 'Contacts');
        }
      } finally {
        _refreshing = false;
        if (!isClosed) isLoading.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  /// 关键词过滤后的扁平列表（搜索态使用）
  List<ContactModel> get filtered {
    final kw = keyword.value.trim();
    if (kw.isEmpty) return _all;
    return _all
        .where(
          (c) => SocialSearch.matches(kw, c.searchName, identifier: c.username),
        )
        .toList();
  }

  /// 按字母分组（普通态使用），组与组内均已排序
  List<ContactGroup> get groups {
    final map = <String, List<ContactModel>>{};
    for (final c in filtered) {
      map.putIfAbsent(c.indexKey, () => []).add(c);
    }
    final letters = map.keys.toList()..sort(_compareIndexKeys);
    return [
      for (final l in letters)
        ContactGroup(l, map[l]!..sort((a, b) => a.name.compareTo(b.name))),
    ];
  }

  /// 首次加载已经取得完整联系人，索引点击只负责定位，不能产生数据副作用。
  bool hasGroup(String letter) {
    final target = letter.trim().toUpperCase();
    return groups.any((group) => group.letter == target);
  }

  static int _compareIndexKeys(String left, String right) {
    if (left == right) return 0;
    if (left == '#') return 1;
    if (right == '#') return -1;
    return left.compareTo(right);
  }

  void openSearch() => topBarMode.value = TopBarMode.search;

  void closeSearch() {
    keyword.value = '';
    topBarMode.value = TopBarMode.normal;
  }

  void updateKeyword(String value) => keyword.value = value;

  void setActiveLetter(String letter) => activeLetter.value = letter;
}
