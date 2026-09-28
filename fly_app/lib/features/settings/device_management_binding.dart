/// 设备管理页面依赖随路由创建和释放，设备列表不跨账号缓存。
library;

import 'package:get/get.dart';

import '../../core/network/api_client.dart';
import '../../data/local/session_storage.dart';
import '../../data/repositories/device_session_repository_impl.dart';
import '../../domain/repositories/device_session_repository.dart';
import 'device_management_controller.dart';

class DeviceManagementBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DeviceSessionRepository>(
      () => DeviceSessionRepositoryImpl(Get.find<ApiClient>()),
    );
    Get.lazyPut<DeviceManagementController>(
      () => DeviceManagementController(
        Get.find<DeviceSessionRepository>(),
        readSessionId: Get.find<SessionStorage>().readSessionId,
      ),
    );
  }
}
