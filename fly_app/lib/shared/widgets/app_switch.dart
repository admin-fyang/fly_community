/// 应用全局统一开关。
///
/// 所有布尔设置统一使用资料详情页既有的紧凑 Cupertino 风格，避免不同页面
/// 混用 Material Switch 后产生尺寸、滑块比例和动画差异。
library;

import 'package:flutter/cupertino.dart';

import '../../core/extensions/context_extension.dart';

/// 全局布尔开关。
///
/// 视觉规格固定为 42×26，开启轨道使用当前主题品牌色；[onChanged] 为空时
/// 进入禁用态。组件仅负责开关本身，标题、副标题和图标由各业务页面布局。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 26,
      child: FittedBox(
        fit: BoxFit.fill,
        child: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: context.tokens.brand,
          inactiveTrackColor: context.isDark
              ? const Color(0xFF39393D)
              : null,
          thumbColor: context.isDark ? const Color(0xFF121212) : null,
          inactiveThumbColor: context.isDark
              ? const Color(0xFF121212)
              : null,
        ),
      ),
    );
  }
}
