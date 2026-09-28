/// 本地媒体地址及其资源释放契约。
library;

class LocalMediaHandle {
  const LocalMediaHandle(this.uri, [this._release]);

  final String uri;
  final void Function()? _release;

  /// Web Blob URL 必须主动回收；原生文件地址无需处理。
  void dispose() => _release?.call();
}

abstract interface class LocalMediaSource {
  LocalMediaHandle? create({String? path, List<int>? bytes, String? mimeType});
}
