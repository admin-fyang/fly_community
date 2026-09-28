/// 公共协议内容展示页。
///
/// 页面只负责将接口已经解析出的 HTML 交给 WebView 渲染，不在 Widget 中请求接口。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../data/models/public_content_page_model.dart';

/// 展示用户协议、隐私政策等公共 HTML 内容。
///
/// 页面不使用导航栏，只在左上角保留轻量返回按钮；协议正文颜色由当前应用
/// 主题驱动，并在运行时切换主题后重新加载对应 HTML 样式。
class PublicContentPage extends StatefulWidget {
  const PublicContentPage({required this.content, super.key});

  final PublicContentPageModel content;

  @override
  State<PublicContentPage> createState() => _PublicContentPageState();
}

class _PublicContentPageState extends State<PublicContentPage> {
  late final WebViewController _webViewController;
  Brightness? _loadedBrightness;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_loadedBrightness == brightness) return;
    _loadedBrightness = brightness;
    _progress = 0;
    final isDark = brightness == Brightness.dark;
    _webViewController
      ..setBackgroundColor(
        isDark ? AppColors.darkBackground : AppColors.lightSurface,
      )
      // baseUrl 让正文中的同源相对资源仍能以 API 域名为基准解析。
      ..loadHtmlString(
        _htmlDocument(widget.content, isDark: isDark),
        baseUrl: AppConfig.apiBaseUrl,
      );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppColors.darkBackground
        : AppColors.lightSurface;
    final foreground = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.square(
                dimension: AppSizes.appBarHeight,
                child: IconButton(
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back, color: foreground),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _htmlDocument(PublicContentPageModel content, {required bool isDark}) {
  final title = const HtmlEscape(HtmlEscapeMode.element).convert(content.title);
  final colorScheme = isDark ? 'dark' : 'light';
  final background = isDark ? '#05080D' : '#FFFFFF';
  final foreground = isDark ? '#F7F9FC' : '#17212B';
  final link = isDark ? '#74C7F2' : '#00658F';
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<meta name="color-scheme" content="$colorScheme only">'
      '<title>$title</title>'
      '<style>'
      ':root{color-scheme:$colorScheme only;}'
      'html,body{background:$background!important;color:$foreground!important;}'
      'body{margin:0;padding:64px 16px 24px;box-sizing:border-box;'
      'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,'
      '"PingFang SC","Microsoft YaHei",sans-serif;font-size:15px;line-height:1.65;}'
      'h1.app-content-title{margin:0 0 16px;font-size:20px;line-height:1.4;'
      'font-weight:600;}'
      'body *{color:$foreground!important;}'
      'img,video{max-width:100%;height:auto;}'
      'body a{color:$link!important;overflow-wrap:anywhere;}'
      '</style></head><body>'
      '${content.showTitle ? '<h1 class="app-content-title">$title</h1>' : ''}'
      '${content.contentHtml}</body></html>';
}
