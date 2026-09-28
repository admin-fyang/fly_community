/// 公共文档外链服务。
///
/// 统一读取 `/system/config` 下发的地址并在应用内 WebView 打开。页面不直接依赖
/// `url_launcher`，便于统一处理未配置、打开失败等状态。
library;

import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_config.dart';
import '../../core/network/api_client.dart';
import '../../routes/app_routes.dart';
import '../models/public_content_page_model.dart';
import 'system_time_service.dart';

enum PublicLinkType { userAgreement, privacyPolicy, faq }

enum PublicLinkOpenResult { opened, notConfigured, failed }

class PublicLinkService {
  const PublicLinkService(this._systemTimeService, this._apiClient);

  final SystemTimeService _systemTimeService;
  final ApiClient _apiClient;

  Future<PublicLinkOpenResult> open(PublicLinkType type) async {
    // 协议入口属于低频操作，每次点击都强制刷新公共配置，避免安装包长期
    // 保留旧域名缓存。刷新失败时才回退到最后一次完整成功快照。
    await _systemTimeService.refresh(force: true);
    final rawUrl = _urlOf(type);

    if (rawUrl == null) return PublicLinkOpenResult.notConfigured;

    try {
      if (rawUrl.startsWith('/')) {
        final content = await _contentPage(rawUrl);
        await Get.toNamed<dynamic>(AppRoutes.publicContent, arguments: content);
        return PublicLinkOpenResult.opened;
      }
      final uri = Uri.tryParse(rawUrl);
      if (uri == null) return PublicLinkOpenResult.failed;
      final opened = await launchUrl(uri, mode: LaunchMode.inAppWebView);
      return opened ? PublicLinkOpenResult.opened : PublicLinkOpenResult.failed;
    } catch (_) {
      return PublicLinkOpenResult.failed;
    }
  }

  String? _urlOf(PublicLinkType type) => switch (type) {
    PublicLinkType.userAgreement => _systemTimeService.userAgreement,
    PublicLinkType.privacyPolicy => _systemTimeService.privacyPolicyUrl,
    PublicLinkType.faq => _systemTimeService.faqUrl,
  };

  /// 系统配置中的站内路径是内容 API，不是可直接交给 WebView 的网页地址。
  /// 必须先通过统一 ApiClient 解析 BaseResponse，再只展示服务端返回的 HTML。
  Future<PublicContentPageModel> _contentPage(String apiPath) async {
    // 配置下发的是以 `/` 开头的 API path。这里显式使用 apiBaseUrl 拼成
    // 完整地址，不能依赖 Dio 对相对路径的隐式解析，否则不同 baseUrl 形式
    // 下可能请求到错误地址。
    final apiUri = Uri.parse(AppConfig.apiBaseUrl).resolve(apiPath);
    final page = await _apiClient.get<PublicContentPageModel>(
      apiUri.toString(),
      requiresAuth: false,
      decoder: (data) => PublicContentPageModel.fromJson(_jsonObject(data)),
    );
    final appName = _systemTimeService.appName?.trim() ?? '';
    return PublicContentPageModel(
      title: page.title.replaceAll('【APP名称】', appName),
      contentHtml: page.contentHtml.replaceAll('【APP名称】', appName),
    );
  }
}

Map<String, dynamic> _jsonObject(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};
