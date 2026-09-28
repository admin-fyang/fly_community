/// 注册步骤指示器。
///
/// 步骤数量随联系方式验证配置动态变化；当前及已完成步骤用品牌色勾选，未来
/// 步骤保留数字，既还原参考稿又不只依靠颜色表达状态。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class RegisterStepIndicator extends StatelessWidget {
  const RegisterStepIndicator({
    super.key,
    required this.stepCount,
    required this.currentIndex,
  });

  final int stepCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '注册步骤 ${currentIndex + 1}，共 $stepCount 步',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < stepCount; index++) ...[
            _StepCircle(index: index, active: index <= currentIndex),
            if (index < stepCount - 1)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 2,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSizes.paddingSm,
                ),
                color: index < currentIndex
                    ? context.tokens.brand
                    : context.colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({required this.index, required this.active});

  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: active ? context.tokens.brand : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: active
              ? context.tokens.brand
              : context.colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: active
          ? const Icon(Icons.check, color: Colors.white, size: 22)
          : Text(
              '${index + 1}',
              style: AppTextStyles.buttonLabel.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
