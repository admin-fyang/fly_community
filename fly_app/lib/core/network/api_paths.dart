/// API 路径常量。
///
/// 路径集中维护，页面和 Controller 不拼接接口地址。
library;

class ApiPaths {
  ApiPaths._();

  static const verificationCodes = '/api/v1/auth/verification-codes';
  static const passwordReset = '/api/v1/auth/password/reset';
  static const systemConfig = '/api/v1/system/config';
  static const register = '/api/v1/auth/register';
  static String usernameAvailability(String username) =>
      '/api/v1/usernames/${Uri.encodeComponent(username)}/availability';
  static const passwordLogin = '/api/v1/auth/login/password';
  static const logout = '/api/v1/auth/logout';
  static const authSessions = '/api/v1/auth/sessions';

  static String authSession(String sessionId) =>
      '$authSessions/${Uri.encodeComponent(sessionId)}';
  static const currentUser = '/api/v1/users/me';
  static const currentUserPassword = '/api/v1/users/me/password';
  static const currentUserPushPreferences = '/api/v1/users/me/push-preferences';

  static String currentUserPushDevice(String deviceId) =>
      '/api/v1/users/me/push-devices/${Uri.encodeComponent(deviceId)}';
  static const accountDeletionRequests = '/api/v1/users/me/deletion-requests';
  static const cancelAccountDeletion =
      '/api/v1/users/me/deletion-requests/cancel';
  static const avatarUploadCredentials =
      '/api/v1/files/avatar/upload-credentials';

  static String completeUpload(String resourceId) =>
      '/api/v1/files/$resourceId/complete';
  static const feedbackUploadCredentials =
      '/api/v1/files/feedback/upload-credentials';
  static const feedbacks = '/api/v1/feedbacks';
  static const feedbackSubmissionToken = '/api/v1/feedbacks/submission-token';

  static const messageUploadCredentials =
      '/api/v1/files/message/upload-credentials';

  static String multipartPartCredentials(String resourceId) =>
      '/api/v1/files/$resourceId/multipart/parts/credentials';

  static String multipartUpload(String resourceId) =>
      '/api/v1/files/$resourceId/multipart';

  static String completeMultipartUpload(String resourceId) =>
      '/api/v1/files/$resourceId/multipart/complete';

  static const currentUserAvatar = '/api/v1/users/me/avatar';
  static const qrResolve = '/api/v1/qr/resolve';

  static const contacts = '/api/v1/contacts';
  static const userSearch = '/api/v1/users/search';
  static const friendRequests = '/api/v1/friend-requests';

  static String userProfile(String userId) => '/api/v1/users/$userId/profile';

  static String contactRemark(String userId) =>
      '/api/v1/contacts/$userId/remark';

  static String contactSettings(String userId) =>
      '/api/v1/contacts/$userId/settings';

  static String contact(String userId) => '/api/v1/contacts/$userId';

  static String contactBlock(String userId) => '/api/v1/contacts/$userId/block';

  static const notifications = '/api/v1/notifications';
  static const notificationUnreadCount = '/api/v1/notifications/unread-count';
  static const notificationReadAll = '/api/v1/notifications/read-all';

  static String notificationRead(String notificationId) =>
      '/api/v1/notifications/$notificationId/read';

  static String notificationHandle(String notificationId) =>
      '/api/v1/notifications/$notificationId/handle';

  static String notification(String notificationId) =>
      '/api/v1/notifications/$notificationId';

  static const imMessages = '/api/v1/im/messages';
  static const imConversations = '/api/v1/im/conversations';
  static const imConversationMessagesMutation =
      '/api/v1/im/conversations/messages';
  static const imConversationMessagesBatch =
      '/api/v1/im/conversations/messages/batch';
  static const imConversationsBatch = '/api/v1/im/conversations/batch';
  static const imConversationsMuteBatch = '/api/v1/im/conversations/mute/batch';
  static const imConversationsPinBatch = '/api/v1/im/conversations/pin/batch';
  static const imSingleConversation = '/api/v1/im/conversations/single';
  static const imSync = '/api/v1/im/sync';
  static const imDirectoryBootstrap = '/api/v1/im/directory/bootstrap';
  static const imProtocolIssues = '/api/v1/im/protocol/issues';
  static const imCentrifugoToken = '/api/v1/im/centrifugo/token';
  static const imCalls = '/api/v1/im/calls';
  static const imLiveGifts = '/api/v1/im/live/gifts';
  static const imFavorites = '/api/v1/im/favorites';

  static String imFavorite(String favoriteId) =>
      '/api/v1/im/favorites/$favoriteId';

  static String imConversationMessages(String conversationId) =>
      '/api/v1/im/conversations/$conversationId/messages';

  static String imConversationRead(String conversationId) =>
      '/api/v1/im/conversations/$conversationId/read';

  static String imMessage(String messageId) => '/api/v1/im/messages/$messageId';

  static String imMessageRecall(String messageId) =>
      '/api/v1/im/messages/$messageId/recall';

  static String imConversationSettings(String conversationId) =>
      '/api/v1/im/conversations/$conversationId/settings';

  static String imCallAnswer(String callId) =>
      '/api/v1/im/calls/$callId/answer';

  static String imCallSnapshotV2(String callId) =>
      '/api/v1/im/calls/$callId/snapshot';

  static String imCallCommandV2(String callId, String action) =>
      '/api/v1/im/calls/$callId/$action';

  static String imCallInvitations(String callId) =>
      '/api/v1/im/calls/$callId/invitations';

  static String imCallJoin(String callId) => '/api/v1/im/calls/$callId/join';

  static String imCallLikes(String callId) => '/api/v1/im/calls/$callId/likes';

  static String imCallGifts(String callId) => '/api/v1/im/calls/$callId/gifts';

  static String imCallReceivedGifts(String callId) =>
      '/api/v1/im/calls/$callId/received-gifts';

  static String imCallLiveSettings(String callId) =>
      '/api/v1/im/calls/$callId/live-settings';

  static String imConversationActiveCall(String conversationId) =>
      '/api/v1/im/conversations/$conversationId/active-call';

  static String imCallToken(String callId) => '/api/v1/im/calls/$callId/token';

  static String imCallUpgradeVideo(String callId) =>
      '/api/v1/im/calls/$callId/upgrade-video';

  static String imCallReject(String callId) =>
      '/api/v1/im/calls/$callId/reject';

  static String imCallHangup(String callId) =>
      '/api/v1/im/calls/$callId/hangup';

  static String imCallTimeout(String callId) =>
      '/api/v1/im/calls/$callId/timeout';
}
