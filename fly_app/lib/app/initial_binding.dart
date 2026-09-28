/// 全局依赖注入装配。
///
/// App 启动即执行,注册在整个生命周期常驻的全局控制器(如主题控制器)。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../core/network/api_client.dart';
import '../core/network/network_recovery_controller.dart';
import '../core/session/session_controller.dart';
import '../core/theme/theme_controller.dart';
import '../data/local/session_storage.dart';
import '../data/local/app_settings_storage.dart';
import '../data/local/system_config_storage.dart';
import '../data/local/im_database_platform.dart';
import '../data/local/im_local_database.dart';
import '../data/local/im_pending_attachment_store.dart';
import '../data/network/client_platform_interceptor.dart';
import '../data/network/safe_dio_log_interceptor.dart';
import '../data/network/auth_interceptor.dart';
import '../data/network/object_storage_client.dart';
import '../data/network/request_id_interceptor.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/account_security_repository_impl.dart';
import '../data/repositories/contact_repository_impl.dart';
import '../data/repositories/im_repository_impl.dart';
import '../data/repositories/message_upload_repository_impl.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../data/repositories/system_config_repository_impl.dart';
import '../data/repositories/user_repository_impl.dart';
import '../data/services/device_service.dart';
import '../data/services/android_local_notification_service.dart';
import '../data/services/notification_branding_service.dart';
import '../data/services/directory_sync_service.dart';
import '../data/services/chat_attachment_picker_service.dart';
import '../data/services/chat_viewport_state_store.dart';
import '../data/services/im_sync_service.dart';
import '../data/services/user_profile_sync_service.dart';
import '../data/services/im_realtime_service.dart';
import '../data/services/im_lifecycle_service.dart';
import '../data/services/im_pending_message_service.dart';
import '../data/services/im_protocol_issue_reporter.dart';
import '../data/services/im_receipt_service.dart';
import '../data/services/system_time_service.dart';
import '../data/services/system_feature_error_interceptor.dart';
import '../data/services/public_link_service.dart';
import '../data/services/image_cache_service.dart';
import '../data/services/file_transfer_service.dart';
import '../features/notifications/notification_unread_controller.dart';
import '../features/notifications/message_reminder_coordinator.dart';
import '../features/settings/chat_settings_controller.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/account_security_repository.dart';
import '../domain/repositories/contact_repository.dart';
import '../domain/repositories/im_repository.dart';
import '../domain/repositories/message_upload_repository.dart';
import '../domain/repositories/notification_repository.dart';
import '../domain/repositories/system_config_repository.dart';
import '../domain/repositories/user_repository.dart';
import '../routes/app_routes.dart';
import 'app_config.dart';
import '../core/session/session_invalidation_service.dart';
import '../data/services/avatar_cache_service.dart';

/// 全局依赖注入：App 启动时常驻的全局控制器
class InitialBinding extends Bindings {
  InitialBinding({
    ImDatabasePlatform? imDatabasePlatform,
    ImRepository? imRepository,
  }) : _imDatabasePlatform = imDatabasePlatform,
       _imRepository = imRepository;

  /// 仅用于测试或受控运行环境覆盖数据库平台。
  ///
  /// 生产启动不传此参数，仍由条件导入选择原生 SQLite 或 Web SQLite WASM；
  /// Widget 测试传入内存实现，避免错误依赖原生插件通道。
  final ImDatabasePlatform? _imDatabasePlatform;

  /// UI/集成测试可替换远端 IM 边界，生产环境仍创建真实仓储。
  final ImRepository? _imRepository;

  @override
  void dependencies() {
    // Web 必须在任何 SQLite 服务被构造前注册 WASM 数据库工厂；原生端为空操作。
    initializeImDatabasePlatform();
    final appSettingsStorage = Get.put<AppSettingsStorage>(
      AppSettingsStorage(),
      permanent: true,
    );
    // 主题控制器全局常驻，启动后恢复当前设备上次选择的模式。
    Get.put<ThemeController>(
      ThemeController(appSettingsStorage),
      permanent: true,
    );
    // 聊天设置与设置页、聊天页、会话列表共享同一份响应式状态。
    Get.put<ChatSettingsController>(
      ChatSettingsController(appSettingsStorage),
      permanent: true,
    );

    final storage = Get.put<SessionStorage>(SessionStorage(), permanent: true);
    final sessionController = Get.put<SessionController>(
      SessionController(storage),
      permanent: true,
    );
    final localNotificationService = Get.put<AndroidLocalNotificationService>(
      AndroidLocalNotificationService(storage, appSettingsStorage),
      permanent: true,
    );
    final pendingAttachmentStore = Get.put<ImPendingAttachmentStore>(
      createImPendingAttachmentStore(),
      permanent: true,
    );
    Get.put<ImLocalDatabase>(
      ImLocalDatabase(
        storage: storage,
        platform: _imDatabasePlatform,
        attachmentStore: pendingAttachmentStore,
      ),
      permanent: true,
    );
    final deviceService = Get.put<DeviceService>(
      DeviceService(storage),
      permanent: true,
    );
    Get.put<SessionInvalidationService>(
      SessionInvalidationService(
        storage: storage,
        session: sessionController,
        cleanups: [
          AvatarCacheService.empty,
          () async {
            if (Get.isRegistered<ImLifecycleService>()) {
              await Get.find<ImLifecycleService>().deactivateSession();
            }
          },
          () async {
            if (Get.isRegistered<ChatViewportStateStore>()) {
              Get.find<ChatViewportStateStore>().clear();
            }
          },
          () async {
            if (Get.isRegistered<NotificationUnreadController>()) {
              Get.find<NotificationUnreadController>().clear();
            }
          },
        ],
        navigateToLogin: () {
          if (!_isAuthRoute(Get.currentRoute)) Get.offAllNamed(AppRoutes.login);
        },
      ),
      permanent: true,
    );
    final dio =
        Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              sendTimeout: AppConfig.connectTimeout,
              contentType: Headers.jsonContentType,
            ),
          )
          ..interceptors.add(RequestIdInterceptor())
          ..interceptors.add(SafeDioLogInterceptor())
          ..interceptors.add(ClientPlatformInterceptor(deviceService))
          ..interceptors.add(
            AuthInterceptor(
              storage,
              onSessionUnauthorized: (id, reason) =>
                  Get.find<SessionInvalidationService>().invalidate(id, reason: reason),
            ),
          );
    final recovery = Get.put<NetworkRecoveryController>(
      NetworkRecoveryController(), permanent: true,
    );
    final client = Get.put<ApiClient>(ApiClient(dio, readAccessToken: storage.readAccessToken, recovery: recovery), permanent: true);
    final directorySyncService = Get.put<DirectorySyncService>(
      DirectorySyncService(client, Get.find<ImLocalDatabase>(), storage),
      permanent: true,
    );
    final systemConfigStorage = Get.put<SystemConfigStorage>(
      SystemConfigStorage(sourceBaseUrl: AppConfig.apiBaseUrl),
      permanent: true,
    );
    final systemConfigRepository = Get.put<SystemConfigRepository>(
      SystemConfigRepositoryImpl(client),
      permanent: true,
    );
    final systemTimeService = Get.put<SystemTimeService>(
      SystemTimeService(systemConfigRepository, systemConfigStorage)
        ..startObserving(),
      permanent: true,
    );
    dio.interceptors.add(SystemFeatureErrorInterceptor(systemTimeService));
    Get.put<NotificationBrandingService>(
      NotificationBrandingService(systemTimeService),
      permanent: true,
    );
    Get.put<PublicLinkService>(
      PublicLinkService(systemTimeService, client),
      permanent: true,
    );
    final storageClient = Get.put<ObjectStorageClient>(
      ObjectStorageClient(
        Dio(
          BaseOptions(
            connectTimeout: AppConfig.connectTimeout,
            sendTimeout: const Duration(minutes: 1),
            receiveTimeout: AppConfig.receiveTimeout,
          ),
        ),
      ),
      permanent: true,
    );

    Get.put<AuthRepository>(
      AuthRepositoryImpl(client, deviceService, storage),
      permanent: true,
    );
    Get.put<AccountSecurityRepository>(
      AccountSecurityRepositoryImpl(client),
      permanent: true,
    );
    Get.put<UserRepository>(
      UserRepositoryImpl(client, storageClient),
      permanent: true,
    );
    Get.put<ContactRepository>(
      ContactRepositoryImpl(
        client,
        Get.find<ImLocalDatabase>(),
        directorySyncService,
      ),
      permanent: true,
    );
    Get.put<NotificationRepository>(
      NotificationRepositoryImpl(client, directorySyncService),
      permanent: true,
    );
    Get.put<NotificationUnreadController>(
      NotificationUnreadController(Get.find<NotificationRepository>()),
      permanent: true,
    );
    final imRepository = Get.put<ImRepository>(
      _imRepository ??
          ImRepositoryImpl(client, storage, Get.find<ImLocalDatabase>()),
      permanent: true,
    );
    final messageUploadRepository = Get.put<MessageUploadRepository>(
      MessageUploadRepositoryImpl(client, storageClient),
      permanent: true,
    );
    final pendingMessageService = Get.put<ImPendingMessageService>(
      ImPendingMessageService(
        Get.find<ImLocalDatabase>(),
        imRepository,
        messageUploadRepository,
        storage,
        pendingAttachmentStore,
      ),
      permanent: true,
    );
    Get.put<ImReceiptService>(
      ImReceiptService(imRepository, Get.find<ImLocalDatabase>(), storage),
      permanent: true,
    );
    Get.put<ChatAttachmentPickerService>(
      SystemChatAttachmentPickerService(),
      permanent: true,
    );
    Get.put<ChatViewportStateStore>(ChatViewportStateStore(), permanent: true);
    Get.put<FileTransferService>(createFileTransferService(), permanent: true);
    Get.put<ImageCacheService>(
      ImageCacheService(),
      permanent: true,
    );
    final protocolIssueReporter = Get.put<ImProtocolIssueReporter>(
      ImProtocolIssueReporter(imRepository, deviceService),
      permanent: true,
    );
    final syncService = Get.put<ImSyncService>(
      ImSyncService(
        imRepository,
        deviceService,
        storage,
        Get.find<ImLocalDatabase>(),
        protocolIssueReporter,
        directorySyncService,
      ),
      permanent: true,
    );
    Get.put<UserProfileSyncService>(
      UserProfileSyncService(syncService, sessionController),
      permanent: true,
    );
    final messageReminders = Get.put<MessageReminderCoordinator>(
      MessageReminderCoordinator(
        storage,
        appSettingsStorage,
        localNotificationService,
      ),
      permanent: true,
    );
    directorySyncService.bindReliableSync(
      applyWriteThroughEvent: syncService.applyWriteThroughEvent,
      requestIncrementalSync: () async {
        await syncService.requestSync(reason: ImSyncReason.manual);
      },
    );
    final realtimeService = Get.put<ImRealtimeService>(
      ImRealtimeService(imRepository, protocolIssueReporter)
        ..readSessionId = storage.readSessionId
        ..onSessionRevoked = (id) => Get.find<SessionInvalidationService>().invalidate(id),
      permanent: true,
    );
    realtimeService.events.listen((event) async {
      try {
        final applyResult = await syncService.applyRealtimeEvent(event);
        await messageReminders.handlePersistedRealtimeEvent(event, applyResult);
      } catch (error) {
        // 实时事件只有成功写入 SQLite 后才会推进游标；失败必须可见，不能静默丢失。
        debugPrint('[IM realtime] 实时事件落库失败：$error');
      }
    });
    localNotificationService.taps.listen((tap) {
      Get.toNamed(AppRoutes.chatFor(tap.conversationId));
    });
    final imLifecycle = Get.put<ImLifecycleService>(
      ImLifecycleService(
        storage,
        syncService,
        realtimeService,
        pendingMessageService,
        Get.find<ImLocalDatabase>(),
        directorySyncService,
        localNotificationService,
        recovery,
      )..startObserving(),
      permanent: true,
    );
    recovery.reconnect = imLifecycle.retryConnection;

  }

  bool _isAuthRoute(String route) {
    return route == AppRoutes.login ||
        route == AppRoutes.register ||
        route == AppRoutes.registerPhone ||
        route == AppRoutes.registerEmail ||
        route == AppRoutes.forgotPassword;
  }
}
