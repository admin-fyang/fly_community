/// 注册流程专用输入框。
///
/// 参考注册稿采用“图标 + 占位文案”的紧凑结构，因此不复用登录页带顶部标签的
/// AuthTextField，避免为了注册改动登录页面已经确认的视觉样式。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class RegisterTextField extends StatefulWidget {
  const RegisterTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.errorText,
    this.supportingText,
    this.supportingColor,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.suffix,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;
  final String? errorText;
  final String? supportingText;
  final Color? supportingColor;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? suffix;
  final int? maxLength;

  @override
  State<RegisterTextField> createState() => _RegisterTextFieldState();
}

class _RegisterTextFieldState extends State<RegisterTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final message = widget.errorText ?? widget.supportingText;
    final messageColor = widget.errorText != null
        ? colors.error
        : widget.supportingColor ?? colors.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: widget.obscure && _obscured,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          maxLength: widget.maxLength,
          style: AppTextStyles.messageBody.copyWith(color: colors.onSurface),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: colors.surfaceContainerHigh,
            hintText: widget.hint,
            hintStyle: AppTextStyles.messageBody.copyWith(
              color: colors.onSurfaceVariant,
            ),
            prefixIcon:
                widget.prefix ??
                Icon(widget.icon, color: colors.onSurfaceVariant, size: 22),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _obscured ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscured = !_obscured),
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colors.onSurfaceVariant,
                      size: 21,
                    ),
                  )
                : widget.suffix,
            border: _border(Colors.transparent),
            enabledBorder: _border(Colors.transparent),
            // 注册稿中输入框聚焦前后均无描边，仅由光标表达焦点状态。
            focusedBorder: _border(Colors.transparent),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingLg,
              vertical: AppSizes.paddingLg,
            ),
          ),
        ),
        if (message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSizes.paddingXs,
              top: AppSizes.paddingXs,
            ),
            child: Text(
              message,
              style: AppTextStyles.metadata.copyWith(color: messageColor),
            ),
          ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
    borderSide: BorderSide.none,
  );
}
