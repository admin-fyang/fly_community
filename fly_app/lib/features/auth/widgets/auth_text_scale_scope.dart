/// 认证页面字体缩放作用域。
library;

import 'package:flutter/material.dart';

/// 统一登录与注册页面的字体缩放基准。
///
/// Android 厂商系统允许用户单独修改“字体大小”，同一设计字号会因此在不同
/// 真机上再次放大或缩小。认证页属于固定结构的短表单，为保证标题、输入提示和
/// 按钮在登录与注册之间保持一致，这里仅在认证页禁用系统文字二次缩放；聊天、
/// 设置等其他页面仍保留系统可访问性缩放能力。
class AuthTextScaleScope extends StatelessWidget {
  const AuthTextScaleScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(child: child);
  }
}
