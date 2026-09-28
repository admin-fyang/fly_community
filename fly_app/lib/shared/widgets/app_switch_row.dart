/// 全局开关行组件。
///
/// 从群资料页 `_switchRow` 提取:标签 + 紧凑 CupertinoSwitch,不带图标。
library;

import 'package:flutter/material.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_switch.dart';

class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.messageBody.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
