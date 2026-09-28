/// 全局统一的空数据与错误反馈组件。
///
/// [AppEmptyState] 只表示请求成功但没有可展示内容，固定使用产品空状态插画；
/// [AppErrorState] 表示请求失败，保留错误语义及明确的重试反馈。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.description,
    this.actionText,
    this.onAction,
    this.assetPath = defaultAssetPath,
    this.tintImage = true,
    this.imageSize = 112,
    this.padding = const EdgeInsets.all(AppSizes.paddingXl),
  });

  static const defaultAssetPath = 'assets/icons/empty_state.svg';

  final String message;
  final String? description;
  final String? actionText;
  final VoidCallback? onAction;

  /// 空状态插画路径。默认仍使用全局通用插画，只有具备明确业务语义的页面
  /// 才传入专用资源，避免各模块重新创建不一致的空状态结构。
  final String assetPath;

  /// 线性通用插画跟随主题文字色；彩色业务插画应关闭着色以保留原始渐变。
  final bool tintImage;

  final double imageSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return _AppStateViewport(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            assetPath,
            width: imageSize,
            height: imageSize,
            fit: BoxFit.contain,
            colorFilter: tintImage
                ? ColorFilter.mode(semantic.textTertiary, BlendMode.srcIn)
                : null,
          ),
          const SizedBox(height: AppSizes.paddingMd),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.messageBody.copyWith(
              color: context.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSizes.paddingXs),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: AppTextStyles.metadata.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onAction != null && actionText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSizes.paddingSm),
            TextButton(onPressed: onAction, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryText = '重新加载',
    this.padding = const EdgeInsets.all(AppSizes.paddingXl),
  });

  final String message;
  final VoidCallback onRetry;
  final String retryText;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return _AppStateViewport(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: semantic.textTertiary,
          ),
          const SizedBox(height: AppSizes.paddingMd),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.metadata.copyWith(
              color: semantic.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.paddingSm),
          TextButton(onPressed: onRetry, child: Text(retryText)),
        ],
      ),
    );
  }
}

/// 空状态与错误状态共用的自适应视口。
///
/// [Center] 给滚动视口提供松约束：可用高度充足时，视口按内容高度收缩并
/// 保持垂直居中；手机横屏、分屏或大字体导致高度不足时，视口占满可用高度并
/// 允许纵向滚动，避免固定尺寸插画和文案触发 `RenderFlex overflow`。
/// 这里不使用 [LayoutBuilder]，确保组件可以安全放进需要查询固有尺寸的
/// `SliverFillRemaining(hasScrollBody: false)`；外部传入的间距保持不变。
class _AppStateViewport extends StatelessWidget {
  const _AppStateViewport({required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }
}
