/// 设备管理页面：参考设备页的圆角分组和三行列表，业务操作由 Controller 处理。
library;

import 'package:flychat/shared/widgets/navigation/app_page_scaffold.dart';
import '../../shared/widgets/loading/app_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/entities/device_session.dart';
import '../../shared/utils/app_feedback.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/interaction/app_pressable.dart';
import '../../shared/widgets/search/app_search_app_bar.dart';
import '../../shared/widgets/section_card.dart';
import 'device_management_controller.dart';
import 'widgets/device_link_card.dart';

class DeviceManagementPage extends GetView<DeviceManagementController> {
  const DeviceManagementPage({super.key});

  static const _pageInset = 12.0;
  static const _groupRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return AppPageScaffold(
      topContentGap: _pageInset,
      extendBodyBehindAppBar: true,
      readActivity: controller.pageReads,
      backgroundColor: colors.backgroundGrouped,
      appBar: AppSearchAppBar(
        title: '设备',
        onBack: () => Navigator.of(context).maybePop(),
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        top: false,
        child: Obx(() {
          final current = controller.currentSession.value;
          final items = controller.items.toList(growable: false);
          final loading = controller.isLoading.value;
          final error = controller.errorMessage.value;
          final loadingMore = controller.isLoadingMore.value;
          final hasMore = controller.hasMore.value;
          if (current == null && loading) return const _DeviceSkeleton();
          if (current == null) {
            return ListView(
              padding: (const EdgeInsets.all(
                _pageInset,
              )).add(EdgeInsets.only(top: appTopBarInset(context))),
              children: [
                const _DeviceLinkIntro(),
                _RetryMessage(
                  message: error.isEmpty ? '设备列表加载失败' : error,
                  onRetry: controller.refreshSessions,
                ),
              ],
            );
          }
          return AppRefreshIndicator(
            onRefresh: controller.refreshSessions,
            child: ListView.builder(
              controller: controller.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: (const EdgeInsets.fromLTRB(
                _pageInset,
                12,
                _pageInset,
                24,
              )).add(EdgeInsets.only(top: appTopBarInset(context))),
              itemCount: items.length + 3,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _DeviceLinkIntro(),
                      const SizedBox(height: 12),
                      if (error.isNotEmpty)
                        _RetryMessage(
                          message: error,
                          onRetry: loading ? null : controller.refreshSessions,
                        ),
                      SectionCard(
                        borderRadius: _groupRadius,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _SectionLabel('此设备'),
                            _DeviceRow(
                              session: current,
                              isCurrent: true,
                              onTap: () =>
                                  _showCurrentDetails(context, current),
                            ),
                            AppPressable(
                              onTap: () => _confirmRevokeAll(context),
                              pressedColor: colors.surfacePressed,
                              semanticLabel: '注销所有其他设备上的会话',
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.pan_tool_outlined,
                                      size: 24,
                                      color: colors.destructive,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        '注销所有其他设备上的会话',
                                        style: AppTextStyles.listTitle.copyWith(
                                          color: colors.destructive,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                        child: Text(
                          '登出除此设备外的所有设备。',
                          style: AppTextStyles.metadata.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                if (index == 1) {
                  return _SessionGroupPart(
                    first: true,
                    last: items.isEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionLabel('活跃会话'),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            child: Text(
                              '暂无其他登录设备',
                              style: AppTextStyles.settingsSubtitle.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (index == items.length + 2) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        if (items.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '点击设备可查看登录详情，并退出其他设备的会话。',
                              style: AppTextStyles.metadata.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        if (hasMore)
                          TextButton(
                            onPressed: loading || loadingMore
                                ? null
                                : controller.loadMore,
                            child: Text(error.isNotEmpty ? '重试加载更多' : '加载更多'),
                          ),
                      ],
                    ),
                  );
                }
                final item = items[index - 2];
                final last = index == items.length + 1;
                return _SessionGroupPart(
                  key: ValueKey('device-session-${item.sessionId}'),
                  last: last,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: last ? 8 : 0),
                    child: _DeviceRow(
                      session: item,
                      onTap: () => _confirmRevoke(context, item),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  /// 本机详情只读，避免将“查看详情”误操作为退出当前登录。
  Future<void> _showCurrentDetails(
    BuildContext context,
    DeviceSession session,
  ) => _showDeviceNotice(
    context,
    title: '此设备',
    message: _sessionDetails(session),
  );

  Future<void> _confirmRevoke(
    BuildContext context,
    DeviceSession session,
  ) async {
    controller.prepareRevoke();
    final success = await AppAsyncConfirmDialog.show(
      title: '设备详情',
      message:
          '${_sessionDetails(session)}\n\n'
          '退出后，此登录会话将失效，需要重新登录。',
      confirmText: '退出登录',
      danger: true,
      onConfirm: () => controller.revoke(session),
      errorBuilder: (context) => Obx(() {
        final message = controller.operationError.value;
        return message.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.metadata.copyWith(
                    color: context.semanticColors.destructive,
                  ),
                ),
              );
      }),
    );
    if (success == true && context.mounted) AppFeedback.show('已退出该登录会话');
  }

  /// 确认后获取完整列表并串行执行；提交中按钮转圈，进度及失败留在弹窗内。
  Future<void> _confirmRevokeAll(BuildContext context) async {
    controller.prepareRevoke();
    final success = await AppAsyncConfirmDialog.show(
      title: '注销其他设备会话',
      message: '将逐个注销全部其他登录会话，此设备保持登录。其他设备需要重新登录，是否继续？',
      confirmText: '注销会话',
      danger: true,
      onConfirm: controller.revokeAllOthers,
      errorBuilder: (context) => Obx(() {
        final error = controller.operationError.value;
        final progress = controller.revokeAllProgress.value;
        if (error.isEmpty && progress.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            error.isNotEmpty ? error : progress,
            textAlign: TextAlign.center,
            style: AppTextStyles.metadata.copyWith(
              color: error.isNotEmpty
                  ? context.semanticColors.destructive
                  : context.semanticColors.textSecondary,
            ),
          ),
        );
      }),
    );
    if (success == true && context.mounted) {
      AppFeedback.show(
        controller.revokedCount.value == 0
            ? '没有需要注销的其他会话'
            : '已注销 ${controller.revokedCount.value} 个其他会话',
      );
    }
  }
}

/// 在功能尚未开放时保留入口，用可关闭说明框反馈，不触发普通社交扫码。
class _DeviceLinkIntro extends StatelessWidget {
  const _DeviceLinkIntro();

  @override
  Widget build(BuildContext context) => DeviceLinkCard(
    onAddDevice: () => _showDeviceNotice(
      context,
      title: '扫码登录 PC 端',
      message: '扫码登录 PC 端暂未开放。开放后，可扫描 PC 端登录页的二维码，并在手机上确认登录。',
    ),
  );
}

/// 只读详情和待开放功能说明共用滚动弹窗，大字体下仍能关闭。
Future<void> _showDeviceNotice(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.semanticColors.surfaceElevated,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    scrollable: true,
    title: Text(title),
    content: Text(
      message,
      style: AppTextStyles.settingsSubtitle.copyWith(
        color: context.semanticColors.textPrimary,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);

/// 每个懒加载单元使用同一表面，仅首尾绘制圆角，形成连续分组而不嵌套滚动。
class _SessionGroupPart extends StatelessWidget {
  const _SessionGroupPart({
    super.key,
    required this.child,
    this.first = false,
    this.last = false,
  });
  final Widget child;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(first ? DeviceManagementPage._groupRadius : 0),
      bottom: Radius.circular(last ? DeviceManagementPage._groupRadius : 0),
    ),
    child: ColoredBox(color: context.semanticColors.surface, child: child),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: AppTextStyles.listTitle.copyWith(
        color: context.semanticColors.accent,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 列表保持设备名、客户端版本、IP/活跃时间三层信息，完整时间在详情中显示。
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.session, this.isCurrent = false, this.onTap});
  final DeviceSession session;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlatformBadge(platform: session.platform),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.deviceName ?? '未知设备',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.listTitle.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_platformName(session.platform)} · ${session.appVersion ?? '未知版本'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.settingsSubtitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${session.loginIp ?? '暂无 IP 记录'} · '
                  '${isCurrent ? '当前会话' : _formatActivity(session.lastActiveAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.settingsSubtitle.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return AppPressable(
      semanticLabel: '查看 ${session.deviceName ?? '未知设备'} 的登录详情',
      onTap: onTap,
      pressedColor: colors.surfacePressed,
      child: child,
    );
  }
}

/// 平台圆形图标采用参考图的绿色、蓝色和粉色分类，颜色不表示在线状态。
class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.platform});
  final String? platform;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (platform) {
      'android' => (Icons.android_rounded, const Color(0xFF78BE46)),
      'ios' => (Icons.phone_iphone_rounded, const Color(0xFF4AADD0)),
      'windows' => (Icons.laptop_windows_rounded, const Color(0xFF4AADD0)),
      'macos' => (Icons.laptop_mac_rounded, const Color(0xFF4AADD0)),
      'web' => (Icons.public_rounded, const Color(0xFFEB7398)),
      _ => (Icons.computer_rounded, const Color(0xFF4AADD0)),
    };
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 27, color: Colors.white),
      ),
    );
  }
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(12, appTopBarInset(context) + 12, 12, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.metadata.copyWith(
            color: context.semanticColors.destructive,
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

/// 首屏骨架沿用相同分组和图标位置，不播放持续动画。
class _DeviceSkeleton extends StatelessWidget {
  const _DeviceSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载登录设备',
    child: ListView.builder(
      padding: EdgeInsets.fromLTRB(12, appTopBarInset(context) + 12, 12, 12),
      itemCount: 3,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: index == 0
            ? const _DeviceLinkIntro()
            : SectionCard(
                borderRadius: DeviceManagementPage._groupRadius,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: context.semanticColors.surfacePressed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(
                            3,
                            (line) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: FractionallySizedBox(
                                widthFactor: line == 0 ? 0.65 : 0.9,
                                child: Container(
                                  height: 12,
                                  color: context.semanticColors.surfacePressed,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}

String _sessionDetails(DeviceSession session) =>
    '${session.deviceName ?? '未知设备'}\n'
    '${_platformName(session.platform)} · ${session.appVersion ?? '未知版本'}\n'
    '登录时间：${_formatTime(session.createdAt)}\n'
    '最近活跃：${_formatTime(session.lastActiveAt)}\n'
    '登录 IP：${session.loginIp ?? '暂无记录'}';

String _platformName(String? platform) => switch (platform) {
  'android' => 'Android',
  'ios' => 'iOS',
  'windows' => 'Windows',
  'macos' => 'macOS',
  'linux' => 'Linux',
  'web' => 'Web',
  _ => '未知平台',
};

String _formatActivity(DateTime? time) {
  if (time == null) return '暂无活跃记录';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}

String _formatTime(DateTime? time) {
  if (time == null) return '暂无记录';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
