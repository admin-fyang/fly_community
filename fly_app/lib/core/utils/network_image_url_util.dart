/// 网络图片地址校验工具。
///
/// 后端图片字段的契约是完整 HTTP/HTTPS 公网地址。纯 UUID、本地路径或缺少
/// host 的 URI 不能交给 Flutter NetworkImage，否则图片解码阶段会抛出异步异常。
abstract final class NetworkImageUrlUtil {
  /// 返回可安全交给 Flutter 网络图片组件的地址；非法值统一返回 null。
  static String? normalize(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }
}
