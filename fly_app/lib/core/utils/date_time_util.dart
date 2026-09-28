/// 时间格式化：会话列表 / 消息时间戳的展示规则
///
/// 第一阶段服务于 Mock 数据展示，规则贴近 Telegram：
/// 今天显示时分，昨天显示「昨天」，本周显示星期，更早显示日期。
library;

import '../time/system_clock.dart';

class DateTimeUtil {
  DateTimeUtil._();

  static const List<String> _weekdays = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 会话列表时间：今天→HH:mm，昨天→昨天，本周→周几，更早→M月d日
  static String conversationTime(DateTime time) {
    final displayTime = SystemClock.toDisplay(time);
    final now = SystemClock.now;
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(
      displayTime.year,
      displayTime.month,
      displayTime.day,
    );
    final diffDays = today.difference(target).inDays;

    if (diffDays == 0) return _hm(displayTime);
    if (diffDays == 1) return '昨天';
    if (diffDays >= 0 && diffDays < 7) {
      return _weekdays[displayTime.weekday - 1];
    }
    return '${displayTime.month}月${displayTime.day}日';
  }

  /// 消息气泡时间：HH:mm
  static String messageTime(DateTime time) =>
      _hm(SystemClock.toDisplay(time));

  /// 聊天日期分割线：今天 / 昨天 / M月d日
  static String dateDivider(DateTime time) {
    final displayTime = SystemClock.toDisplay(time);
    final now = SystemClock.now;
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(
      displayTime.year,
      displayTime.month,
      displayTime.day,
    );
    final diffDays = today.difference(target).inDays;

    if (diffDays == 0) return '今天';
    if (diffDays == 1) return '昨天';
    return '${displayTime.month}月${displayTime.day}日';
  }

  /// 内部:格式化为两位补零的 HH:mm
  static String _hm(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
