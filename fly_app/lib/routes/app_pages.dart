/// 社区版页面注册表：账号、联系人、单聊、通知和基础设置。
library;

import 'package:get/get.dart';

import '../core/constants/app_constants.dart';
import '../core/navigation/telegram_page_transition.dart';
import '../core/session/session_controller.dart';
import '../data/local/im_local_database.dart';
import '../data/local/im_pending_attachment_store.dart';
import '../data/models/public_content_page_model.dart';
import '../data/services/file_transfer_service.dart';
import '../data/services/image_cache_service.dart';
import '../features/auth/forgot_password_binding.dart';
import '../features/auth/forgot_password_page.dart';
import '../features/auth/login_binding.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_binding.dart';
import '../features/auth/register_page.dart';
import '../features/chat/chat_binding.dart';
import '../features/chat/flutter_chat_page.dart';
import '../features/main_navigation/main_navigation_binding.dart';
import '../features/main_navigation/main_navigation_controller.dart';
import '../features/main_navigation/main_navigation_page.dart';
import '../features/media_preview/media_preview_controller.dart';
import '../features/media_preview/media_preview_page.dart';
import '../features/notifications/friend_request_detail_binding.dart';
import '../features/notifications/friend_request_detail_page.dart';
import '../features/notifications/notifications_binding.dart';
import '../features/notifications/notifications_page.dart';
import '../features/profile/profile_binding.dart';
import '../features/profile/profile_detail_page.dart';
import '../features/public_content/public_content_page.dart';
import '../features/search/search_binding.dart';
import '../features/search/search_page.dart';
import '../features/settings/account_security_controller.dart';
import '../features/settings/account_settings_page.dart';
import '../features/settings/change_password_controller.dart';
import '../features/settings/change_password_page.dart';
import '../features/settings/chat_settings_page.dart';
import '../features/settings/data_settings_page.dart';
import '../features/settings/delete_account_controller.dart';
import '../features/settings/delete_account_page.dart';
import '../features/settings/device_management_binding.dart';
import '../features/settings/device_management_page.dart';
import '../features/settings/edit_profile_binding.dart';
import '../features/settings/edit_profile_page.dart';
import '../features/settings/settings_binding.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/theme_settings_page.dart';
import 'app_routes.dart';
import 'system_feature_middleware.dart';

class AppPages {
  AppPages._();

  static const initial = AppRoutes.login;
  static final _telegramPageTransition = TelegramPageTransition();
  static const _specialTransitionRoutes = <String>{
    AppRoutes.login,
    AppRoutes.registerPhone,
    AppRoutes.registerEmail,
    AppRoutes.register,
    AppRoutes.forgotPassword,
    AppRoutes.mediaPreview,
  };

  /// 普通页面沿用已有转场；媒体预览保留原来的上滑转场。
  static final routes = _baseRoutes.map((route) {
    if (_specialTransitionRoutes.contains(route.name)) return route;
    return route.copy(
      customTransition: _telegramPageTransition,
      transitionDuration: AppConstants.animSlow,
    );
  }).toList(growable: false);

  static final _baseRoutes = <GetPage>[
    GetPage(name: AppRoutes.login, page: () => const LoginPage(), binding: LoginBinding()),
    GetPage(name: AppRoutes.register, page: () => const RegisterPage(), binding: RegisterBinding(), middlewares: [SystemFeatureMiddleware(SystemFeature.registration)]),
    GetPage(name: AppRoutes.registerPhone, page: () => const RegisterPage(), binding: RegisterBinding(), middlewares: [SystemFeatureMiddleware(SystemFeature.registration)]),
    GetPage(name: AppRoutes.registerEmail, page: () => const RegisterPage(), binding: RegisterBinding(), middlewares: [SystemFeatureMiddleware(SystemFeature.registration)]),
    GetPage(name: AppRoutes.forgotPassword, page: () => const ForgotPasswordPage(), binding: ForgotPasswordBinding()),
    GetPage(name: AppRoutes.publicContent, page: () => PublicContentPage(content: Get.arguments as PublicContentPageModel)),
    GetPage(name: AppRoutes.conversations, page: () => const MainNavigationPage(), binding: MainNavigationBinding(MainTab.conversations)),
    GetPage(name: AppRoutes.mine, page: () => const MainNavigationPage(), binding: MainNavigationBinding(MainTab.mine)),
    GetPage(name: AppRoutes.chat, page: () => const FlutterChatPage(), binding: ChatBinding()),
    GetPage(
      name: AppRoutes.mediaPreview,
      page: () => const MediaPreviewPage(),
      binding: BindingsBuilder(() {
        Get.lazyPut<MediaPreviewController>(() => MediaPreviewController(
          Get.arguments as MediaPreviewArguments,
          Get.find<FileTransferService>(),
          Get.find<ImLocalDatabase>(),
          Get.find<ImPendingAttachmentStore>(),
          Get.find<ImageCacheService>(),
          Get.find<SessionController>(),
        ));
      }),
      transition: Transition.downToUp,
      transitionDuration: const Duration(milliseconds: 260),
    ),
    GetPage(name: AppRoutes.contacts, page: () => const MainNavigationPage(), binding: MainNavigationBinding(MainTab.contacts)),
    GetPage(name: AppRoutes.contactDetail, page: () => const ProfileDetailPage(), binding: ProfileBinding()),
    GetPage(name: AppRoutes.strangerDetail, page: () => const ProfileDetailPage(), binding: ProfileBinding()),
    GetPage(name: AppRoutes.contactSearch, page: () => const SearchPage(), binding: SearchBinding()),
    GetPage(name: AppRoutes.notifications, page: () => const NotificationsPage(), binding: NotificationsBinding()),
    GetPage(name: AppRoutes.friendRequestDetail, page: () => const FriendRequestDetailPage(), binding: FriendRequestDetailBinding()),
    GetPage(name: AppRoutes.settings, page: () => const SettingsPage(), binding: SettingsBinding()),
    GetPage(name: AppRoutes.deviceManagement, page: () => const DeviceManagementPage(), binding: DeviceManagementBinding()),
    GetPage(name: AppRoutes.editProfile, page: () => const EditProfilePage(), binding: EditProfileBinding()),
    GetPage(name: AppRoutes.accountSettings, page: () => const AccountSettingsPage(), binding: BindingsBuilder(() => Get.lazyPut<AccountSecurityController>(AccountSecurityController.new))),
    GetPage(name: AppRoutes.changePassword, page: () => const ChangePasswordPage(), binding: BindingsBuilder(() => Get.lazyPut<ChangePasswordController>(ChangePasswordController.new))),
    GetPage(name: AppRoutes.deleteAccount, page: () => const DeleteAccountPage(), binding: BindingsBuilder(() => Get.lazyPut<DeleteAccountController>(DeleteAccountController.new))),
    GetPage(name: AppRoutes.chatSettings, page: () => const ChatSettingsPage()),
    GetPage(name: AppRoutes.themeSettings, page: () => const ThemeSettingsPage()),
    GetPage(name: AppRoutes.dataSettings, page: () => const DataSettingsPage()),
  ];
}
