/// 好友申请详情页依赖注入。
library;

import 'package:get/get.dart';

import 'friend_request_detail_controller.dart';

class FriendRequestDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<FriendRequestDetailController>(
      () => FriendRequestDetailController(),
    );
  }
}
