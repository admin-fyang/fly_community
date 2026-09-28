/// 页面读取任务的 GetX 状态。只登记页面主动读取，不监听全局 HTTP 或同步任务。
library;

import 'package:get/get.dart';

/// 按任务标识记录在途读取；不同任务可并行，拒绝重复执行的入口也能安全结束。
///
/// 返回的结束回调必须放入 finally。旧请求结束不能清除新请求的标识，缓存
/// 命中也不会提前结束服务器刷新。关闭后不再接收任务，防止页面退出后残留状态。
class PageReadActivity {
  final _tasks = <Object, String>{}.obs;

  /// 读取失败的局部文案，由页面骨架呈现；后台同步不调用此接口。
  final errorMessage = ''.obs;
  bool _closed = false;

  bool get isReading => _tasks.isNotEmpty;

  /// visible 为 false 时用于复用读取方法的后台同步入口，不展示页面加载动画。
  void Function() begin(String channel, {bool replace = false, bool visible = true}) {
    if (_closed || !visible) return () {};
    final token = Object();
    errorMessage.value = '';
    if (replace) _tasks.removeWhere((_, value) => value == channel);
    _tasks[token] = channel;
    return () {
      if (!_closed) _tasks.remove(token);
    };
  }

  /// 查询条件整体切换时撤销旧查询的展示标识。请求本身仍由业务层取消或丢弃；
  /// 旧 finally 仅删除自己的 token，不会关闭新查询的加载图标。
  void reset() {
    if (_closed) return;
    _tasks.clear();
    errorMessage.value = '';
  }

  void reportError(String message) {
    if (!_closed) errorMessage.value = message;
  }

  void dismissError() => errorMessage.value = '';

  void close() {
    _closed = true;
    _tasks.clear();
  }
}

/// 页面业务控制器复用的读取生命周期；不包含保存、发送或上传等写入状态。
mixin PageReadTracking on GetxController {
  final pageReads = PageReadActivity();

  @override
  void onClose() {
    pageReads.close();
    super.onClose();
  }
}
