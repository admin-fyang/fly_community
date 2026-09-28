/// 应用统一服务器时钟。
///
/// 消息模型始终保存 UTC 绝对时间；只有展示阶段才转换为系统配置下发的
/// IANA 时区。这样终端时区或终端时钟错误不会改变已确认消息的显示结果。
library;

import 'package:timezone/timezone.dart' as tz;

class SystemClock {
  SystemClock._();

  static const defaultTimeZoneName = 'Asia/Shanghai';
  static tz.Location _location = tz.UTC;
  static DateTime? _serverAnchorUtc;
  static Stopwatch _elapsed = Stopwatch();

  static String get timeZoneName => _location.name;

  /// 应用一次系统配置。
  ///
  /// [serverTimeSeconds] 只使用本次在线响应值建立单调时钟锚点；读取历史缓存
  /// 时不传该值，避免把上次启动时的旧服务器时间当成当前时间。
  static bool configure({
    required String timeZoneName,
    int? serverTimeSeconds,
  }) {
    var validLocation = true;
    try {
      _location = tz.getLocation(timeZoneName);
    } catch (_) {
      validLocation = false;
      _location = tz.getLocation(defaultTimeZoneName);
    }
    _elapsed.stop();
    _elapsed = Stopwatch()..start();
    _serverAnchorUtc =
        serverTimeSeconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
              serverTimeSeconds * 1000,
              isUtc: true,
            );
    return validLocation;
  }

  /// 当前绝对时间。在线配置成功后由服务器时间加单调计时推导。
  static DateTime get nowUtc =>
      _serverAnchorUtc?.add(_elapsed.elapsed) ?? DateTime.now().toUtc();

  static tz.TZDateTime get now => tz.TZDateTime.from(nowUtc, _location);

  /// 把任意绝对时间转换为服务器配置时区；不读取终端时区。
  static tz.TZDateTime toDisplay(DateTime instant) =>
      tz.TZDateTime.from(instant.toUtc(), _location);
}
