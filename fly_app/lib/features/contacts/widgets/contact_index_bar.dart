/// 联系人字母索引条组件。
///
/// 右侧 A–Z/# 快速索引,点击/滑动定位到对应分组。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';

/// 右侧 A–Z 索引条
///
/// 点击字母回调 [onSelect]；顶部星标回调 [onTapStar]（跳到列表顶部）。
/// 当前高亮字母由 [activeLetter] 控制。
class ContactIndexBar extends StatelessWidget {
  const ContactIndexBar({
    super.key,
    required this.activeLetter,
    required this.onSelect,
    required this.onTapStar,
  });

  final String activeLetter;
  final ValueChanged<String> onSelect;
  final VoidCallback onTapStar;

  static const List<String> _letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onTapStar,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Icon(Icons.star, size: 12, color: colors.onSurfaceVariant),
          ),
        ),
        for (final l in _letters)
          GestureDetector(
            onTap: () => onSelect(l),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
              child: Text(
                l,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      activeLetter == l ? FontWeight.w700 : FontWeight.w500,
                  color:
                      activeLetter == l
                          ? context.tokens.brand
                          : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
