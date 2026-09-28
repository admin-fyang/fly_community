/// 公共协议内容模型。
///
/// 对应 `/api/v1/system/content-pages/{slug}` 的 `data`，只保留协议展示所需字段。
class PublicContentPageModel {
  const PublicContentPageModel({
    required this.title,
    required this.contentHtml,
    this.showTitle = false,
  });

  final String title;
  final String contentHtml;

  /// 协议正文通常已经包含自身标题；帮助文章正文不包含标题，需要由统一 HTML
  /// 容器补充。显式区分可避免协议页重复显示标题。
  final bool showTitle;

  factory PublicContentPageModel.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim() ?? '';
    final contentHtml = json['content_html']?.toString().trim() ?? '';
    if (title.isEmpty || contentHtml.isEmpty) {
      throw const FormatException('公共内容页面缺少标题或正文');
    }
    return PublicContentPageModel(title: title, contentHtml: contentHtml);
  }
}
