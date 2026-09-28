/// 文本派生颜色工具。
///
/// 由字符串稳定地映射到调色板中的一种颜色,保证同名对象(如同一用户)
/// 在字母头像与昵称等处着色一致。
library;

import 'package:flutter/material.dart';

/// 由文本稳定派生颜色：同名总是同色
///
/// 用于字母头像背景、群聊发送者昵称着色，保证同一用户在头像与昵称处颜色一致。
class ColorUtil {
  ColorUtil._();

  /// 柔和调色板，避免高饱和大色块（贴合克制风格）
  static const List<Color> palette = [
    Color(0xFF4F9DDD),
    Color(0xFF2CB5B5),
    Color(0xFF6C7BD6),
    Color(0xFFE57399),
    Color(0xFFE0A458),
    Color(0xFF7E9B57),
    Color(0xFF9B72CF),
    Color(0xFF55A868),
  ];

  /// 将文本按字符码求和后对调色板取模,得到稳定颜色
  static Color fromText(String text) {
    if (text.isEmpty) return palette.first;
    final hash = text.codeUnits.fold<int>(0, (p, c) => p + c);
    return palette[hash % palette.length];
  }
}
