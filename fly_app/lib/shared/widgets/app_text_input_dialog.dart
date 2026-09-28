/// 全局单文本输入弹窗。
///
/// 用于好友申请验证信息、拒绝原因、邀请留言、入群申请等“一个文本框 +
/// 取消/确认”的轻量输入场景。业务方只负责提交文本并返回是否成功。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_text_styles.dart';
import 'interaction/app_pressable.dart';

class AppTextInputDialog extends StatefulWidget {
  const AppTextInputDialog({
    super.key,
    required this.title,
    required this.onConfirm,
    this.description,
    this.hintText,
    this.initialValue = '',
    this.maxLength,
    this.minLines = 4,
    this.maxLines = 4,
    this.confirmText = '确定',
    this.emptyConfirmText,
    this.cancelText = '取消',
    this.hideCancelWhenSubmitting = true,
  });

  final String title;
  final String? description;
  final String? hintText;
  final String initialValue;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final String confirmText;
  final String? emptyConfirmText;
  final String cancelText;
  final bool hideCancelWhenSubmitting;
  final Future<bool> Function(String text) onConfirm;

  static Future<bool?> show({
    required String title,
    required Future<bool> Function(String text) onConfirm,
    String? description,
    String? hintText,
    String initialValue = '',
    int? maxLength,
    int minLines = 4,
    int maxLines = 4,
    String confirmText = '确定',
    String? emptyConfirmText,
    String cancelText = '取消',
    bool hideCancelWhenSubmitting = true,
    bool barrierDismissible = true,
  }) {
    return Get.dialog<bool>(
      AppTextInputDialog(
        title: title,
        description: description,
        hintText: hintText,
        initialValue: initialValue,
        maxLength: maxLength,
        minLines: minLines,
        maxLines: maxLines,
        confirmText: confirmText,
        emptyConfirmText: emptyConfirmText,
        cancelText: cancelText,
        hideCancelWhenSubmitting: hideCancelWhenSubmitting,
        onConfirm: onConfirm,
      ),
      barrierDismissible: barrierDismissible,
    );
  }

  @override
  State<AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<AppTextInputDialog> {
  late final TextEditingController _controller;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final confirmLabel = _controller.text.trim().isEmpty
        ? widget.emptyConfirmText ?? widget.confirmText
        : widget.confirmText;
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);

    return Dialog(
      elevation: 0,
      backgroundColor: semantic.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTextStyles.navTitleMobile.copyWith(
                        color: semantic.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.description!,
                        style: AppTextStyles.metadata.copyWith(
                          color: semantic.textSecondary,
                          fontSize: 13,
                          height: 18 / 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      enabled: !_isSubmitting,
                      minLines: widget.minLines,
                      maxLines: widget.maxLines,
                      maxLength: widget.maxLength,
                      onChanged: (_) => setState(() {}),
                      cursorColor: semantic.accent,
                      style: AppTextStyles.messageBody.copyWith(
                        color: semantic.textPrimary,
                        fontSize: 15,
                        height: 20 / 15,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: widget.hintText,
                        hintStyle: AppTextStyles.messageBody.copyWith(
                          color: semantic.placeholder,
                          fontSize: 15,
                          height: 20 / 15,
                        ),
                        filled: true,
                        fillColor: context.isDark
                            ? semantic.surface
                            : semantic.backgroundGrouped,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: semantic.accent.withValues(alpha: 0.55),
                            width: hairline,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: hairline,
                child: ColoredBox(color: semantic.separator),
              ),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    // 提交时即使隐藏取消文案，也必须保留左侧按钮槽位；否则右侧
                    // 确定按钮会扩展到整行，加载指示器便会从“确定”位置跳到居中。
                    Expanded(
                      child: _isSubmitting && widget.hideCancelWhenSubmitting
                          ? const SizedBox.expand()
                          : AppPressable(
                              semanticLabel: widget.cancelText,
                              onTap: _isSubmitting
                                  ? null
                                  : () => Get.back<bool>(result: false),
                              child: Center(
                                child: Text(
                                  widget.cancelText,
                                  style: AppTextStyles.messageBody.copyWith(
                                    color: semantic.accent,
                                    fontSize: 15,
                                    height: 20 / 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    SizedBox(
                      width: hairline,
                      child: ColoredBox(color: semantic.separator),
                    ),
                    Expanded(
                      child: AppPressable(
                        semanticLabel: confirmLabel,
                        onTap: _isSubmitting ? null : _confirm,
                        child: Center(
                          child: _isSubmitting
                              ? SizedBox.square(
                                  dimension: 17,
                                  child: AppLoadingIndicator(
                                    size: 17,
                                    color: semantic.accent,
                                  ),
                                )
                              : Text(
                                  confirmLabel,
                                  style: AppTextStyles.messageBody.copyWith(
                                    color: semantic.accent,
                                    fontSize: 15,
                                    height: 20 / 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _isSubmitting = true);
    final ok = await widget.onConfirm(_controller.text);
    if (!mounted) return;
    if (ok) {
      Get.back<bool>(result: true);
      return;
    }
    setState(() => _isSubmitting = false);
  }
}
