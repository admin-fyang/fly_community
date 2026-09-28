/// 全局搜索页依赖注入。
///
/// 进入搜索页时惰性注册其控制器。
library;

import 'package:get/get.dart';

import '../../data/local/search_history_storage.dart';
import 'search_controller.dart';

class SearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SearchHistoryStorage>(() => SearchHistoryStorage());
    Get.lazyPut<GlobalSearchController>(
      () => GlobalSearchController(historyStorage: Get.find()),
    );
  }
}
