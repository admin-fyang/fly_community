/// 开发日志工具。
///
/// 仅在 debug 构建下输出,release 自动静默,避免日志泄漏到生产环境。
library;

import 'package:flutter/foundation.dart';

/// 开发日志：仅在 debug 模式输出，release 自动静默
class LogUtil {
  LogUtil._();

  /// 输出一条调试日志,[tag] 用于标识来源模块
  static void d(Object? message, {String tag = 'APP'}) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }
}
