/// 全局对话框组件。
///
/// 提供成功弹窗 [AppSuccessDialog] 与确认/删除弹窗 [AppConfirmDialog],
/// 各带便捷静态 show 方法,供全局统一调用。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_text_styles.dart';
import 'interaction/app_pressable.dart';

/// 全局成功弹窗
///
/// 居中卡片:成功图标 + 标题 + 描述 + 确定按钮。
/// 充值 / 提现 / 添加收款方式等操作完成后统一调用 [show]。
class AppSuccessDialog extends StatelessWidget {
  const AppSuccessDialog({
    super.key,
    this.title = '操作成功',
    this.message = '您的操作已顺利完成，资金 / 信息已实时更新。',
    this.onConfirm,
  });

  final String title;
  final String message;

  /// 点击「确定」的回调;为空时仅关闭弹窗
  final VoidCallback? onConfirm;

  /// 弹出成功弹窗
  static Future<void> show({
    String title = '操作成功',
    String message = '您的操作已顺利完成，资金 / 信息已实时更新。',
    VoidCallback? onConfirm,
  }) {
    return Get.dialog(
      AppSuccessDialog(title: title, message: message, onConfirm: onConfirm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 42),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(color: semantic.surfaceElevated),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: semantic.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.check_rounded,
                      color: semantic.success,
                      size: 27,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.navTitleMobile.copyWith(
                      color: semantic.textPrimary,
                      fontSize: 16.5,
                      height: 21 / 16.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.metadata.copyWith(
                      color: semantic.textSecondary,
                      fontSize: 13.5,
                      height: 19 / 13.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AppPressable(
                      semanticLabel: '确定',
                      onTap: onConfirm ?? Get.back,
                      normalColor: semantic.accent,
                      pressedColor: semantic.accent.withValues(alpha: 0.82),
                      scaleWhenPressed: 0.99,
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Text(
                            '确定',
                            style: AppTextStyles.messageBody.copyWith(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
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
}

/// 全局确认弹窗(删除 / 危险操作确认)
///
/// [danger] 为真时确认按钮用危险色。通过 [show] 返回用户是否确认。
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.confirmText = '确定',
    this.cancelText = '取消',
    this.danger = false,
  });

  final String title;
  final String? message;
  final String confirmText;
  final String cancelText;
  final bool danger;

  /// 弹出确认弹窗,返回 true 表示用户确认
  static Future<bool?> show({
    required String title,
    String? message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool danger = false,
  }) {
    return Get.dialog<bool>(
      AppConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        danger: danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final confirmColor = danger ? semantic.destructive : semantic.accent;
    return _CompactActionDialog(
      title: title,
      message: message,
      actions: [
        _DialogAction(
          label: cancelText,
          color: semantic.textPrimary,
          onTap: () => Get.back(result: false),
        ),
        _DialogAction(
          label: confirmText,
          color: confirmColor,
          emphasized: true,
          onTap: () => Get.back(result: true),
        ),
      ],
    );
  }
}

/// 带提交 Loading 的异步确认弹窗。
///
/// 异步期间确认按钮显示旋转进度并禁用取消/重复提交；回调返回 false 时保留
/// 弹窗，让调用方展示明确错误后允许用户重试。
class AppAsyncConfirmDialog extends StatefulWidget {
  const AppAsyncConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onConfirm,
    this.errorBuilder,
    this.confirmText = '确定',
    this.danger = false,
  });

  final String title;
  final String message;
  final String confirmText;
  final bool danger;
  final Future<bool> Function() onConfirm;

  /// 可选内联错误区域。由调用页面监听业务状态，失败时留在弹窗内重试。
  final WidgetBuilder? errorBuilder;

  static Future<bool?> show({
    required String title,
    required String message,
    required Future<bool> Function() onConfirm,
    WidgetBuilder? errorBuilder,
    String confirmText = '确定',
    bool danger = false,
  }) => Get.dialog<bool>(
    AppAsyncConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      danger: danger,
      onConfirm: onConfirm,
      errorBuilder: errorBuilder,
    ),
    barrierDismissible: false,
  );

  @override
  State<AppAsyncConfirmDialog> createState() => _AppAsyncConfirmDialogState();
}

class _AppAsyncConfirmDialogState extends State<AppAsyncConfirmDialog> {
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final succeeded = await widget.onConfirm();
    if (!mounted) return;
    if (succeeded) {
      Get.back(result: true);
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final confirmColor =
        widget.danger ? semantic.destructive : semantic.accent;
    return PopScope(
      canPop: !_submitting,
      child: _CompactActionDialog(
        extra: widget.errorBuilder == null ? null : Builder(builder: widget.errorBuilder!),
        title: widget.title,
        message: widget.message,
        actions: [
          _DialogAction(
            label: '取消',
            color: semantic.textPrimary,
            enabled: !_submitting,
            onTap: () => Get.back(),
          ),
          _DialogAction(
            label: widget.confirmText,
            color: confirmColor,
            emphasized: true,
            enabled: !_submitting,
            loading: _submitting,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

class _CompactActionDialog extends StatelessWidget {
  const _CompactActionDialog({
    required this.title,
    required this.actions,
    this.message,
    this.extra,
  });

  final String title;
  final String? message;
  final Widget? extra;
  final List<_DialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);
    return Dialog(
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 42),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(color: semantic.surfaceElevated),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.navTitleMobile.copyWith(
                              color: semantic.textPrimary,
                              fontSize: 16.5,
                              height: 21 / 16.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (extra != null) extra!,
                          if (message?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.messageBody.copyWith(
                                color: semantic.textSecondary,
                                fontSize: 14,
                                height: 20 / 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: hairline, child: ColoredBox(color: semantic.separator)),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0)
                          SizedBox(
                            width: hairline,
                            child: ColoredBox(color: semantic.separator),
                          ),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.emphasized = false,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool emphasized;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return semantic.surfacePressed;
          return Colors.transparent;
        }),
        child: Center(
          child: loading
              ? SizedBox.square(
                  dimension: 17,
                  child: AppLoadingIndicator(size: 17, color: color),
                )
              : Text(
                  label,
                  style: AppTextStyles.messageBody.copyWith(
                    color: enabled ? color : semantic.textDisabled,
                    fontSize: 15,
                    fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
        ),
      ),
    );
  }
}

