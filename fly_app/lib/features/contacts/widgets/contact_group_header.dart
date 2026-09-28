/// 联系人分组字母头组件。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

class ContactGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  const ContactGroupHeaderDelegate(
    this.letter, {
    required this.backgroundColor,
    required this.textColor,
  });

  /// 由页面传入当前主题颜色，主题变化时通过 shouldRebuild 刷新分组头。
  final Color backgroundColor;
  final Color textColor;

  static const double height = 26;
  final String letter;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLg),
      color: backgroundColor,
      child: MediaQuery.withNoTextScaling(
        child: Text(
          letter,
          style: AppTextStyles.metadata.copyWith(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(ContactGroupHeaderDelegate oldDelegate) =>
      oldDelegate.letter != letter ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}
