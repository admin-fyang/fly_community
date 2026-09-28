/// 用户资料页控制器。
///
/// 提供资料详情数据,布局由 detail.isStranger 驱动(好友态/陌生人态)。
library;

import 'package:flychat/shared/widgets/navigation/page_read_activity.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/network/api_exception.dart';
import '../../core/time/system_clock.dart';
import '../../core/utils/log_util.dart';
import '../../data/enums/conversation_type.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/im_api_models.dart';
import '../../data/models/profile_detail_model.dart';
import '../../data/services/system_time_service.dart';
import '../chat/chat_navigation.dart';
import '../../domain/repositories/contact_repository.dart';
import '../../domain/repositories/im_repository.dart';
import '../../routes/app_routes.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/app_text_input_dialog.dart';
import '../../shared/widgets/app_dialog.dart';

/// 用户详情页状态
///
/// 纯展示:从 [Get.arguments] 传入的 [ContactModel] 解析出 [detail]。
/// 第一阶段所有操作仅做 UI 反馈(提示条 / 确认弹窗),不含真实业务逻辑。
class ProfileController extends GetxController with PageReadTracking {
  late ProfileDetailModel detail;
  final version = 0.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final remark = ''.obs;
  final isPinned = false.obs;
  final isMuted = false.obs;
  final isBlocked = false.obs;
  final SystemTimeService systemConfig = Get.find<SystemTimeService>();

  bool get canSendMessage =>
      systemConfig.canChatWith(isFriend: !detail.isStranger);

  bool get canAddFriend {
    systemConfig.revision.value;
    return detail.canAddFriend && systemConfig.canAddFriend;
  }

  String get phoneText =>
      detail.phone.trim().isEmpty ? '未公开' : detail.phone.trim();

  String get lastSeenText {
    final value = detail.lastSeen.trim().isNotEmpty
        ? detail.lastSeen.trim()
        : detail.presence.trim();
    return value.isEmpty ? '未公开' : value;
  }

  String get birthdayText {
    final value = detail.birthday;
    if (value == null) return '未公开';
    return '${value.year}年${value.month}月${value.day}日';
  }

  String get registerTimeText {
    final seconds = detail.registerTime;
    if (seconds == null) return '未公开';
    final utc = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    final value = SystemClock.toDisplay(utc);
    return '${value.year}年${value.month}月${value.day}日';
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    // 首屏只使用路由携带的真实联系人快照，随后再由详情接口刷新完整字段。
    // 禁止使用 MockProfiles 兜底，否则接口返回前会短暂展示虚构资料。
    detail = args is ContactModel
        ? ProfileDetailModel(
            id: args.id,
            publicId: args.publicId,
            name: args.name,
            avatarUrl: args.avatarUrl,
            presence: args.statusText,
            isOnline: args.isOnline,
            username: args.username ?? '',
            isStranger:
                args.relationship != 'friend' && args.relationship != 'self',
          )
        : const ProfileDetailModel(name: '未知用户');
    if (args is ContactModel) {
      remark.value = args.remark ?? '';
      isPinned.value = args.isPinned;
      isMuted.value = args.isMuted;
      unawaited(loadProfile(args.id));
    }
  }

  // ===== 通用操作(静态反馈)=====

  /// 先由服务端幂等解析单聊会话，避免把用户 ID 误作会话 ID。
  Future<void> sendMessage() async {
    if (!canSendMessage) {
      AppToast.warning('当前仅允许好友之间私聊');
      return;
    }
    if (detail.id.isEmpty) return;
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final conversation = await Get.find<ImRepository>()
          .resolveSingleConversation(detail.id);
      if (conversation.type != ConversationType.single ||
          conversation.peerUserId != detail.id) {
        throw const FormatException('单聊会话解析结果与目标用户不一致');
      }
      await ChatNavigation.open(conversation, replaceCurrentWhenNoChat: true);
    } on ApiException catch (error) {
      if (error.code == 'IM_PRIVATE_CHAT_DISABLED') {
        await systemConfig.refresh(force: true);
        AppToast.show('当前仅允许好友之间私聊', type: AppToastType.warning);
      } else {
        AppToast.show('打开会话失败：${error.message}', type: AppToastType.error);
      }
    } catch (_) {
      AppToast.show('打开会话失败，请稍后重试', type: AppToastType.error);
    } finally {
      isLoading.value = false;
    }
  }

  void editRemark() {
    AppTextInputDialog.show(
      title: '修改备注',
      hintText: '请输入联系人备注',
      initialValue: remark.value,
      maxLength: 32,
      minLines: 1,
      maxLines: 1,
      confirmText: '保存',
      onConfirm: (text) => updateRemark(text.trim()),
    );
  }

  Future<bool> updateRemark(String value) async {
    if (detail.id.isEmpty) return false;
    try {
      await Get.find<ContactRepository>().updateRemark(
        userId: detail.id,
        remark: value,
      );
      remark.value = value;
      AppToast.show(
        value.isEmpty ? '已清除备注' : '备注已更新',
        type: AppToastType.success,
      );
      return true;
    } catch (_) {
      AppToast.show('备注更新失败', type: AppToastType.error);
      return false;
    }
  }

  Future<void> togglePinned(bool value) async {
    await _updateSettings(isPinnedValue: value);
  }

  Future<void> toggleMuted(bool value) async {
    await _updateSettings(isMutedValue: value);
  }

  Future<void> loadProfile(String userId) async {
    final finishPageRead = pageReads.begin('loadProfile');
    try {
      isLoading.value = true;
      errorMessage.value = '';
      try {
        detail = await Get.find<ContactRepository>().getUserProfile(userId);
        version.value++;
      } catch (error) {
        if (detail.id.isEmpty) {
          errorMessage.value = '用户资料加载失败';
        } else {
          LogUtil.d('后台刷新失败，继续显示本地用户资料：$error', tag: 'Profile');
        }
      } finally {
        isLoading.value = false;
      }
    } finally {
      finishPageRead();
    }
  }

  Future<void> addContact() async {
    await sendFriendRequest('');
  }

  void showAddContactDialog() {
    AppTextInputDialog.show(
      title: '验证信息',
      description: '简单介绍一下自己',
      hintText: '你好，我想添加你为联系人...',
      maxLength: 100,
      confirmText: '发送请求',
      onConfirm: (text) => sendFriendRequest(text.trim()),
    );
  }

  Future<bool> sendFriendRequest(String remark) async {
    if (detail.id.isEmpty) return false;
    if (!systemConfig.canAddFriend) {
      AppToast.show('添加联系人功能暂未开放', type: AppToastType.warning);
      return false;
    }
    try {
      await Get.find<ContactRepository>().requestFriend(
        targetUserId: detail.id,
        remark: remark,
      );
      AppToast.show('已发送好友请求', type: AppToastType.success);
      return true;
    } on ApiException catch (error) {
      AppToast.error(error.message);
      return false;
    } catch (_) {
      AppToast.show('好友申请发送失败', type: AppToastType.error);
      return false;
    }
  }

  /// 好友资料按单聊对象 ID 清空；服务端不存在共享线程时幂等成功且不会创建会话。
  void confirmClearConversation() {
    if (detail.id.isEmpty) return;
    AppAsyncConfirmDialog.show(
      title: '清空聊天记录',
      message: '确定清空与该联系人的聊天记录吗？此操作只影响你自己。',
      confirmText: '清空',
      danger: true,
      onConfirm: _clearConversation,
    );
  }

  Future<bool> _clearConversation() async {
    try {
      await Get.find<ImRepository>().clearConversationMessages(
        ConversationLocator.byObject(
          type: ConversationType.single,
          objectId: detail.id,
        ),
      );
      AppToast.show('聊天记录已清空', type: AppToastType.success);
      return true;
    } on ApiException catch (error) {
      AppToast.show('清空聊天记录失败：${error.message}', type: AppToastType.error);
      return false;
    } catch (_) {
      AppToast.show('清空聊天记录失败，请稍后重试', type: AppToastType.error);
      return false;
    }
  }

  // ===== 危险操作(确认弹窗)=====

  void confirmDelete() {
    _confirm(
      title: '删除好友',
      message: '确定要删除该联系人吗?删除后将无法撤销。',
      confirmLabel: '删除',
      onConfirm: () => _deleteContact(),
    );
  }

  void confirmBlock() {
    _confirm(
      title: isBlocked.value ? '取消拉黑' : '拉黑用户',
      message: isBlocked.value
          ? '确定要将该用户移出黑名单吗?'
          : '您确定要拉黑该用户吗?拉黑后您将不再收到对方的消息。',
      confirmLabel: isBlocked.value ? '取消拉黑' : '拉黑',
      onConfirm: () => isBlocked.value ? _unblockContact() : _blockContact(),
    );
  }

  // ===== 私有:提示条与确认弹窗 =====

  Future<void> _deleteContact() async {
    if (detail.id.isEmpty) return;
    try {
      await Get.find<ContactRepository>().deleteContact(detail.id);
      AppToast.show('已删除好友', type: AppToastType.success);
    } catch (_) {
      AppToast.show('删除好友失败', type: AppToastType.error);
    }
  }

  Future<void> _updateSettings({
    bool? isPinnedValue,
    bool? isMutedValue,
  }) async {
    if (detail.id.isEmpty) return;
    final oldPinned = isPinned.value;
    final oldMuted = isMuted.value;
    if (isPinnedValue != null) isPinned.value = isPinnedValue;
    if (isMutedValue != null) isMuted.value = isMutedValue;
    try {
      await Get.find<ContactRepository>().updateSettings(
        userId: detail.id,
        isPinned: isPinnedValue,
        isMuted: isMutedValue,
      );
    } catch (_) {
      isPinned.value = oldPinned;
      isMuted.value = oldMuted;
      AppToast.show('联系人设置更新失败', type: AppToastType.error);
    }
  }

  Future<void> _blockContact() async {
    if (detail.id.isEmpty) return;
    try {
      await Get.find<ContactRepository>().blockUser(detail.id);
      isBlocked.value = true;
      AppToast.show('已拉黑用户', type: AppToastType.success);
    } catch (_) {
      AppToast.show('拉黑用户失败', type: AppToastType.error);
    }
  }

  Future<void> _unblockContact() async {
    if (detail.id.isEmpty) return;
    try {
      await Get.find<ContactRepository>().unblockUser(detail.id);
      isBlocked.value = false;
      AppToast.show('已取消拉黑', type: AppToastType.success);
    } catch (_) {
      AppToast.show('取消拉黑失败', type: AppToastType.error);
    }
  }

  void _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    Get.dialog(
      _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        onConfirm: () {
          Get.back();
          onConfirm();
        },
      ),
    );
  }
}

/// 危险操作确认弹窗:圆角、标题+说明、取消 / 危险色确认
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final colors = Theme.of(context).colorScheme;
    final danger = Theme.of(context).extension<AppColorTokens>()!.danger;

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.navTitle.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: AppSizes.paddingSm),
            Text(
              message,
              style: AppTextStyles.messageBody.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSizes.paddingLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSizes.paddingSm),
                TextButton(
                  onPressed: onConfirm,
                  child: Text(confirmLabel, style: TextStyle(color: danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
