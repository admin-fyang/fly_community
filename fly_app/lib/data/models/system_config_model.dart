/// 公开系统配置模型。
library;

class SystemConfigModel {
  SystemConfigModel({
    required this.configVersion,
    required this.timeZoneName,
    required this.offset,
    required this.offsetSeconds,
    required this.serverTime,
    required this.uploadMaxMb,
    required this.openRegister,
    required this.phoneRegisterVerification,
    required this.emailRegisterVerification,
    required this.inviteRegister,
    required this.openUpload,
    required this.privateChat,
    required this.openAddFriend,
    required this.androidForegroundServiceEnabled,
    required this.userAgreement,
    required this.privacyPolicy,
    required this.thirdPartySdk,
    required this.personalInformation,
    required this.minorPrivacy,
    required this.communityGuidelines,

    // this.serviceAgreementUrl,
    // this.privacyPolicyUrl,
    this.faqUrl,
    this.logoUrl,
    this.appName,
    required Iterable<String> noAllowUploadExtensions,
    required Iterable<String> noAllowUploadMimeTypes,
  }) : noAllowUploadExtensions = Set.unmodifiable(noAllowUploadExtensions),
       noAllowUploadMimeTypes = Set.unmodifiable(noAllowUploadMimeTypes);

  static const defaultUploadMaxMb = 100;

  final int configVersion;
  final String timeZoneName;
  final String offset;
  final int offsetSeconds;
  final int serverTime;
  final int uploadMaxMb;
  final bool openRegister;
  final bool phoneRegisterVerification;
  final bool emailRegisterVerification;
  final bool inviteRegister;
  final bool openUpload;
  final bool privateChat;
  final bool openAddFriend;
  final String userAgreement;
  final String privacyPolicy;
  final String thirdPartySdk;
  final String personalInformation;
  final String minorPrivacy;
  final String communityGuidelines;

  /// Android 是否启用独立前台服务长连接；Firebase 始终启用，不受此项控制。
  final bool androidForegroundServiceEnabled;

  /// 服务协议、隐私政策和常见问题地址均由后端配置，客户端不得硬编码。
  // final String? serviceAgreementUrl;
  // final String? privacyPolicyUrl;
  final String? faqUrl;

  /// 由公开系统配置下发的应用品牌 Logo。
  final String? logoUrl;

  /// app名称
  final String? appName;

  /// 禁止上传的扩展名，统一为不带点的小写形式。
  final Set<String> noAllowUploadExtensions;

  /// 禁止上传的 MIME，统一为小写形式。
  final Set<String> noAllowUploadMimeTypes;

  int get uploadMaxBytes => uploadMaxMb * 1024 * 1024;

  /// 客户端仅用公开配置做选择后的即时反馈，服务端仍必须执行最终校验。
  bool isUploadTypeDenied({
    required String filename,
    required String mimeType,
  }) {
    final normalizedName = filename.trim().toLowerCase();
    final deniedByExtension = noAllowUploadExtensions.any(
      (extension) => normalizedName.endsWith('.$extension'),
    );
    if (deniedByExtension) return true;

    final normalizedMime = _normalizeMimeType(mimeType);
    return normalizedMime.isNotEmpty &&
        noAllowUploadMimeTypes.contains(normalizedMime);
  }

  factory SystemConfigModel.fromJson(Map<String, dynamic> json) {
    final timezone = _object(json['timezone']);
    final noAllowUpload = _object(json['no_allow_upload']);
    final name = timezone['name']?.toString().trim() ?? '';
    final serverTime = _int(json['server_time']);
    if (name.isEmpty || serverTime == null || serverTime <= 0) {
      throw const FormatException('系统配置缺少有效的 timezone.name 或 server_time');
    }
    return SystemConfigModel(
      configVersion: _int(json['config_version']) ?? 0,
      timeZoneName: name,
      offset: timezone['offset']?.toString() ?? '',
      offsetSeconds: _int(timezone['offset_seconds']) ?? 0,
      serverTime: serverTime,
      uploadMaxMb: _positiveInt(json['upload_max']) ?? defaultUploadMaxMb,
      openRegister: _enabledFlag(json['open_register']),
      phoneRegisterVerification: _enabledFlag(
        json['phone_register_verification'],
      ),
      emailRegisterVerification: _enabledFlag(
        json['email_register_verification'],
      ),
      inviteRegister: _enabledFlag(json['invite_register']),
      openUpload: _enabledFlag(json['open_upload']),
      privateChat: _enabledFlag(json['private_chat']),
      openAddFriend: _enabledFlag(json['open_add_friend']),
      androidForegroundServiceEnabled: _enabledFlag(
        json['android_foreground_service_enabled'],
      ),

      userAgreement: _nullableUrl(json['user_agreement'])!,
      privacyPolicy: _nullableUrl(json['privacy_policy'])!,
      thirdPartySdk: _nullableUrl(json['third_party_sdk'])!,
      personalInformation: _nullableUrl(json['personal_information'])!,
      minorPrivacy: _nullableUrl(json['minor_privacy'])!,
      communityGuidelines: _nullableUrl(json['community_guidelines'])!,

      faqUrl: _nullableUrl(json['faq_url']),
      logoUrl: _nullableUrl(json['logo_url']),
      appName: json['app_name'],
      noAllowUploadExtensions: _normalizedValues(
        json['extensions'] ?? noAllowUpload['extensions'],
        _normalizeExtension,
      ),
      noAllowUploadMimeTypes: _normalizedValues(
        json['mime_types'] ?? noAllowUpload['mime_types'],
        _normalizeMimeType,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'config_version': configVersion,
    'timezone': {
      'name': timeZoneName,
      'offset': offset,
      'offset_seconds': offsetSeconds,
    },
    'server_time': serverTime,
    'upload_max': uploadMaxMb,
    'open_register': openRegister ? 1 : 0,
    'phone_register_verification': phoneRegisterVerification ? 1 : 0,
    'email_register_verification': emailRegisterVerification ? 1 : 0,
    'invite_register': inviteRegister ? 1 : 0,
    'open_upload': openUpload ? 1 : 0,
    'private_chat': privateChat ? 1 : 0,
    'open_add_friend': openAddFriend ? 1 : 0,
    'android_foreground_service_enabled': androidForegroundServiceEnabled
        ? 1
        : 0,
    // 'service_agreement_url': serviceAgreementUrl,
    // 'privacy_policy_url': privacyPolicyUrl,
    "user_agreement": userAgreement,
    "privacy_policy": privacyPolicy,
    "third_party_sdk": thirdPartySdk,
    "personal_information": personalInformation,
    "minor_privacy": minorPrivacy,
    "community_guidelines": communityGuidelines,

    'faq_url': faqUrl,
    'logo_url': logoUrl,
    'app_name': appName,
    'extensions': noAllowUploadExtensions.toList(growable: false),
    'mime_types': noAllowUploadMimeTypes.toList(growable: false),
  };
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

int? _int(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

int? _positiveInt(Object? value) {
  final parsed = _int(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

/// 后端正式协议使用整数 0/1；兼容布尔值只用于灰度期间的脏数据保护。
bool _enabledFlag(Object? value) =>
    value == 1 || value == true || value?.toString().trim() == '1';

Set<String> _normalizedValues(
  Object? value,
  String Function(String value) normalize,
) {
  if (value is! List) return const {};
  return {
    for (final item in value)
      if (normalize(item.toString()).isNotEmpty) normalize(item.toString()),
  };
}

String _normalizeExtension(String value) =>
    value.trim().toLowerCase().replaceFirst(RegExp(r'^\.+'), '');

String _normalizeMimeType(String value) =>
    value.trim().toLowerCase().split(';').first.trim();

String? _nullableUrl(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  // 内容页接口由公开配置返回同源 API 路径；它不是无效 URL，后续由
  // PublicLinkService 使用当前 API baseUrl 解析。禁止在模型层把它丢成 null，
  // 否则任一内容页字段使用相对路径都会导致整份系统配置解析失败。
  if (text.startsWith('/') && !text.startsWith('//')) return text;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return text;
}
