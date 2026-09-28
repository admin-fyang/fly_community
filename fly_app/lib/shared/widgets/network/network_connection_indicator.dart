/// 公共顶部栏连接标识。
///
/// 仅在断网、查询重试耗尽或恢复中占用一个标准操作位；正常时不占宽度。
/// 图标颜色使用现有主题，Tooltip/读屏提供明确文案；点击立即显示旋转指示器，
/// 恢复期间禁用重复点击。组件只渲染状态、转发事件，不执行网络或修改状态。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/network_recovery_controller.dart';
import '../../../core/extensions/context_extension.dart';
import '../loading/app_loading_indicator.dart';

class NetworkConnectionIndicator extends StatelessWidget {
  const NetworkConnectionIndicator({super.key, this.foregroundColor});

  /// 透明通话/媒体顶栏可传白色，保持重连动画在画面上可读。
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NetworkRecoveryController>()) {
      return const SizedBox.shrink();
    }
    final controller = Get.find<NetworkRecoveryController>();
    return Obx(() {
      if (!controller.visible) return const SizedBox.shrink();
      final retrying = controller.retrying.value;
      final label = retrying ? controller.label : '${controller.label}，点击重试';
      return Semantics(
        liveRegion: true,
        child: IconButton(
          key: const ValueKey('network-connection-indicator'),
          tooltip: label,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          onPressed: retrying ? null : controller.retry,
          icon: retrying
              ? AppLoadingIndicator(
                  size: 16,
                  color: foregroundColor,
                  semanticsLabel: controller.label,
                )
              : Icon(
                  controller.offline.value
                      ? Icons.wifi_off_rounded
                      : Icons.cloud_off_outlined,
                  size: 20,
                  color: context.colorScheme.error,
                ),
        ),
      );
    });
  }
}
