/// 社区版 Web 页面路由。
library;

abstract class AppRoutes {
  static const login = '/login';
  static const registerPhone = '/register/phone';
  static const registerEmail = '/register/email';
  static const register = '/register';
  static const forgotPassword = '/password/forgot';

  static const conversations = '/conversations';
  static const mine = '/mine';
  static const chat = '/chat';
  static String chatFor(String conversationId) =>
      '$chat?conversation_id=${Uri.encodeQueryComponent(conversationId)}';
  static const mediaPreview = '/chat/media/preview';

  static const contacts = '/contacts';
  static const contactSearch = '/contacts/search';
  static const contactDetail = '/contacts/detail';
  static const strangerDetail = '/contacts/stranger';

  static const notifications = '/notifications';
  static const friendRequestDetail = '/notifications/friend-request';
  static const settings = '/settings';
  static const publicContent = '/public-content';
  static const deviceManagement = '/settings/devices';
  static const editProfile = '/settings/profile';
  static const accountSettings = '/settings/account';
  static const changePassword = '/settings/account/password';
  static const deleteAccount = '/settings/account/delete';
  static const chatSettings = '/settings/chat';
  static const themeSettings = '/settings/theme';
  static const dataSettings = '/settings/data';
}
