/// 认证页主按钮组件。
///
/// 登录/注册页的主行动按钮(填充样式)。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';

/// 认证页主行动按钮:整宽品牌色 + 前进箭头。登录 / 注册共用。
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.showTrailingIcon = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool showTrailingIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.tokens.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
          ),
        ),
        child: loading
            ? const SizedBox.square(
                dimension: 20,
                child: AppLoadingIndicator(size: 20, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (showTrailingIcon) ...[
                    const SizedBox(width: AppSizes.paddingSm),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ],
              ),
      ),
    );
  }
}
