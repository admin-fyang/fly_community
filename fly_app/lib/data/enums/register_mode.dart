/// 注册方式枚举。
///
/// 手机号与邮箱两种注册表单同构,仅首字段不同,由本枚举携带各自文案/图标/键盘类型。
library;

import 'package:flutter/material.dart';

/// 注册方式:手机号 / 邮箱
///
/// 两种方式表单同构,仅首个字段(手机号/邮箱)不同,由此枚举驱动切换。
enum RegisterMode {
  phone('手机号', '请输入手机号', Icons.smartphone, TextInputType.phone),
  email('邮箱', '请输入邮箱', Icons.mail_outline, TextInputType.emailAddress);

  const RegisterMode(this.label, this.hint, this.icon, this.keyboardType);

  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
}
