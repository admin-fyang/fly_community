/// 好友申请详情页控制器。
///
/// 负责从通知快照构建首屏资料、拉取用户公开资料、处理同意/拒绝动作。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'package:get/get.dart';

import '../../data/enums/notification_kind.dart';
import '../../data/models/notification_model.dart';
import '../../data/models/profile_detail_model.dart';
import '../../domain/repositories/contact_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_text_input_dialog.dart';
import 'notification_unread_controller.dart';

class FriendRequestDetailController extends GetxController
    with PageReadTracking {
  static const maxReasonLength = 255;

  late NotificationModel notification;
  late ProfileDetailModel detail;

  final version = 0.obs;
  final isLoading = false.obs;
  final isHandling = false.obs;
  final errorMessage = ''.obs;
  final resultAction = ''.obs;
  final resultTextReady = false.obs;
  final hasChanged = false.obs;

  bool get isFriendRequest => notification.notificationType == 'friend_request';

  bool get isFriendRejected =>
      notification.notificationType == 'friend_rejected';

  bool get canHandle =>
      isFriendRequest && notification.actionStatus == 'pending';

  String get requestRemark => notification.requestRemark;

  String get detailReason =>
      isFriendRejected ? notification.rejectReason : notification.requestRemark;

  String get reasonTitle => isFriendRejected ? '拒绝原因' : '申请备注';

  String get emptyReasonText => isFriendRejected ? '对方未填写拒绝原因' : '对方未填写申请备注';

  void showQrCode() => AppToast.show('展示二维码');

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    notification = args is NotificationModel
        ? args
        : const NotificationModel(
            kind: NotificationKind.friendRequest,
            title: '好友申请',
            subtitle: '',
          );
    detail = _snapshotDetail(notification);
    _loadProfile();
  }

  Future<void> accept() async {
    if (!canHandle || isHandling.value) return;
    isHandling.value = true;
    try {
      final updated = await Get.find<NotificationRepository>().handle(
        notificationId: notification.notificationId,
        action: 'accept',
      );
      notification = updated;
      hasChanged.value = true;
      await Get.find<NotificationUnreadController>().refreshCount();
      _startResultAnimation('accepted');
      AppToast.success('已同意好友申请');
    } catch (_) {
      AppToast.error('同意好友申请失败');
    } finally {
      isHandling.value = false;
    }
  }

  Future<void> showRejectDialog() async {
    if (!canHandle || isHandling.value) return;
    final rejected = await AppTextInputDialog.show(
      title: '拒绝申请',
      description: '可填写拒绝原因',
      hintText: '请输入拒绝原因...',
      maxLength: maxReasonLength,
      confirmText: '确定',
      emptyConfirmText: '忽略',
      barrierDismissible: false,
      onConfirm: reject,
    );
    if (rejected == true) {
      _startResultAnimation('rejected');
    }
  }

  Future<bool> reject(String reason) async {
    if (!canHandle || isHandling.value) return false;
    isHandling.value = true;
    try {
      final normalized = reason.trim();
      final updated = await Get.find<NotificationRepository>().handle(
        notificationId: notification.notificationId,
        action: 'reject',
        reason: normalized.isEmpty ? null : normalized,
      );
      notification = updated;
      hasChanged.value = true;
      await Get.find<NotificationUnreadController>().refreshCount();
      AppToast.success(normalized.isEmpty ? '已忽略好友申请' : '已拒绝好友申请');
      return true;
    } catch (_) {
      AppToast.error('拒绝好友申请失败');
      return false;
    } finally {
      isHandling.value = false;
    }
  }

  Future<void> _loadProfile() async {
    final finishPageRead = pageReads.begin('_loadProfile');
    try {
      final userId = notification.friendRequestUserId;
      if (userId.isEmpty) return;
      isLoading.value = true;
      errorMessage.value = '';
      try {
        detail = await Get.find<ContactRepository>().getUserProfile(userId);
        version.value++;
      } catch (_) {
        errorMessage.value = '用户资料加载失败';
      } finally {
        isLoading.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  ProfileDetailModel _snapshotDetail(NotificationModel n) {
    return ProfileDetailModel(
      id: n.friendRequestUserId,
      name: n.actorName,
      avatarUrl: n.actorAvatarUrl,
      presence: n.subtitle,
      bio: n.subtitle,
      username: n.actorUser['username'] is String
          ? n.actorUser['username'] as String
          : n.payload['username'] is String
          ? n.payload['username'] as String
          : '',
      isStranger: true,
      canAddFriend: true,
    );
  }

  void _startResultAnimation(String action) {
    resultTextReady.value = false;
    resultAction.value = action;
  }

  void markResultTextReady() {
    if (resultAction.value.isNotEmpty) {
      resultTextReady.value = true;
    }
  }
}
