/// 全局搜索页控制器。
///
/// 管理搜索关键词与用户/陌生人/群组的命中结果。
library;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/local/search_history_storage.dart';
import '../../data/models/contact_model.dart';
import '../../domain/repositories/contact_repository.dart';
import '../../routes/app_routes.dart';

/// 全局搜索页状态
///
/// 空态展示搜索类别与历史；结果以服务端为准，点击进入既有资料流程。
class GlobalSearchController extends GetxController {
  GlobalSearchController({required SearchHistoryStorage historyStorage})
    : _historyStorage = historyStorage;

  final SearchHistoryStorage _historyStorage;

  final textController = TextEditingController();
  final keyword = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final recentKeywords = <String>[].obs;
  final _userResults = <ContactModel>[].obs;
  late final Worker _keywordWorker;

  /// 输入变化立即使旧请求失效，防止较慢响应覆盖当前类型和搜索词。
  int _searchRevision = 0;

  bool get hasKeyword => keyword.value.trim().isNotEmpty;

  /// 关键词过滤后的用户结果(按昵称或用户名匹配)
  List<ContactModel> get userResults {
    return _userResults;
  }

  bool get hasResults => userResults.isNotEmpty;

  /// 该用户是否已是好友(结果行展示「好友」标记)
  bool isFriend(ContactModel c) => c.relationship == 'friend';

  static const _categories = ['@用户名', '昵称'];

  List<String> get categories => _categories;

  @override
  void onInit() {
    super.onInit();
    _loadRecentKeywords();
    _keywordWorker = debounce<String>(
      keyword,
      (_) => _search(),
      time: const Duration(milliseconds: 300),
    );
  }

  /// 保留原始输入；清空时立即清除结果并使所有在途请求失效。
  void onChanged(String value) {
    if (keyword.value == value) return;
    errorMessage.value = '';
    _searchRevision++;
    keyword.value = value;
    isLoading.value = value.trim().isNotEmpty;
    if (!isLoading.value) {
      _userResults.clear();
    }
  }

  /// 选择最近搜索关键词时，保持与手动输入一致的搜索链路。
  void selectRecentKeyword(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;

    textController.text = normalized;
    textController.selection = TextSelection.collapsed(
      offset: normalized.length,
    );
    onChanged(normalized);
  }

  void clear() {
    errorMessage.value = '';
    _searchRevision++;
    textController.clear();
    keyword.value = '';
    isLoading.value = false;
    _userResults.clear();
  }

  /// 两类请求使用同一份含类型标记的输入，结果不再进行客户端名称过滤。
  Future<void> _search() async {
    final kw = keyword.value.trim();
    final revision = _searchRevision;
    errorMessage.value = '';
    if (kw.isEmpty) {
      _userResults.clear();
      return;
    }

    isLoading.value = true;
    try {
      final results = await Get.find<ContactRepository>().searchUsers(keyword: kw);
      if (isClosed || revision != _searchRevision) return;
      _userResults.assignAll(results);
    } catch (_) {
      if (isClosed || revision != _searchRevision) return;
      errorMessage.value = '搜索失败，请稍后重试';
      _userResults.clear();
    } finally {
      if (!isClosed && revision == _searchRevision) {
        isLoading.value = false;
        try {
          final history = await _historyStorage.saveKeyword(kw);
          if (!isClosed && revision == _searchRevision) {
            recentKeywords.assignAll(history);
          }
        } catch (_) {
          // 历史持久化失败不改变已经完成的搜索结果。
        }
      }
    }
  }

  Future<void> _loadRecentKeywords() async {
    try {
      recentKeywords.assignAll(await _historyStorage.readKeywords());
    } catch (_) {
      recentKeywords.clear();
    }
  }

  void openUser(ContactModel c) =>
      Get.toNamed(AppRoutes.contactDetail, arguments: c);

  @override
  void onClose() {
    errorMessage.value = '';
    _searchRevision++;
    _keywordWorker.dispose();
    textController.dispose();
    super.onClose();
  }
}
