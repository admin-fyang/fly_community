/// 全局统一的局部加载指示器。
///
/// 首次无缓存数据仍优先使用骨架屏；本组件只用于分页、按钮和局部刷新，
/// 避免各页面自行设置颜色、尺寸和线宽导致视觉不一致。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 20,
    this.color,
    this.semanticsLabel = '加载中',
  });

  final double size;
  final Color? color;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: size,
        /*child: CupertinoActivityIndicator(
          radius: size / 2,
          color: color ?? context.semanticColors.accent,
        ),*/
        child: CircularProgressIndicator(
          color: color ?? context.semanticColors.accent,
        ),
      ),
    );
  }
}
