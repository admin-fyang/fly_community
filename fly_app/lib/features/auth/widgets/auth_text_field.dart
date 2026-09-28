/// 认证页输入框组件。
///
/// 登录/注册页统一样式的文本输入框(带前置图标)。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

/// 认证表单输入项
///
/// 顶部 label + 带前置图标的输入框。密码类([obscure] 为真)自带显隐眼睛切换;
/// 其余可传 [suffix](如「获取验证码」按钮)。登录 / 注册页各字段共用。
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.controller,
    this.keyboardType,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.prefix,
    this.suffix,
    this.trailingLabel,
    this.onTrailingLabelTap,
  });

  final String label;
  final String hint;
  final IconData icon;

  /// 密码字段:隐藏文本并显示眼睛切换
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// 输入框左侧自定义部件，手机号地区号等场景使用；为空时展示 [icon]。
  final Widget? prefix;

  /// 输入框右侧自定义部件(非密码字段生效),如「获取验证码」
  final Widget? suffix;

  /// label 右侧的次要链接文案,如「忘记密码?」
  final String? trailingLabel;
  final VoidCallback? onTrailingLabelTap;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured = widget.obscure;

  /// 8px 圆角、无边线的输入框边框(三态一致)
  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
    borderSide: BorderSide.none,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSizes.paddingXs, bottom: 6),
          child: Row(
            children: [
              Text(
                widget.label,
                style: AppTextStyles.metadata.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.trailingLabel != null) ...[
                const Spacer(),
                GestureDetector(
                  onTap: widget.onTrailingLabelTap,
                  child: Text(
                    widget.trailingLabel!,
                    style: AppTextStyles.metadata.copyWith(
                      color: context.tokens.brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        TextField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          enabled: widget.enabled,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          style: AppTextStyles.messageBody.copyWith(color: colors.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.surfaceContainerHigh,
            hintText: widget.hint,
            hintStyle: AppTextStyles.messageBody.copyWith(
              color: colors.outline,
            ),
            prefixIcon:
                widget.prefix ??
                Icon(widget.icon, size: 20, color: colors.outline),
            suffixIcon: _suffix(context),
            // 显式锁定三态边框为 8px 圆角矩形(与登录原型一致),
            // 避免被全局主题的胶囊默认带偏,聚焦时也不变形。
            border: _border,
            enabledBorder: _border,
            focusedBorder: _border,
            contentPadding: const EdgeInsets.symmetric(
              vertical: AppSizes.paddingMd,
            ),
          ),
        ),
      ],
    );
  }

  Widget? _suffix(BuildContext context) {
    if (widget.obscure) {
      return IconButton(
        icon: Icon(
          _obscured ? Icons.visibility : Icons.visibility_off,
          size: 20,
          color: context.colorScheme.outline,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }
    return widget.suffix;
  }
}
