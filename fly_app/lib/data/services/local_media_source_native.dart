/// 原生端直接把应用私有文件路径转换为 file URI。
library;

import 'local_media_source_contract.dart';

LocalMediaSource createLocalMediaSource() => const _NativeLocalMediaSource();

class _NativeLocalMediaSource implements LocalMediaSource {
  const _NativeLocalMediaSource();

  @override
  LocalMediaHandle? create({String? path, List<int>? bytes, String? mimeType}) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.contains('://')) return LocalMediaHandle(value);
    return LocalMediaHandle(Uri.file(value).toString());
  }
}
