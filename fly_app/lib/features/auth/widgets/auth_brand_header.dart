/// 认证页品牌头部组件。
///
/// 登录/注册页顶部的品牌标识与标题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/services/system_time_service.dart';
import '../../../shared/widgets/icons/airplane_float.dart';

/// 认证页头部:品牌图标 + 应用名 + 主副标题。登录 / 注册共用。
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.logo,
  });

  final String title;
  final String subtitle;
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      children: [
        if(logo) _AppLogo(brandColor: context.tokens.brand),
        const SizedBox(height: AppSizes.paddingMd),
        _AppName(color: colors.onSurface),
        const SizedBox(height: AppSizes.paddingXl),
        Text(
          title,
          style: AppTextStyles.navTitle.copyWith(
            color: colors.onSurface,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: AppSizes.paddingXs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.messageBody.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AppName extends StatelessWidget {
  const _AppName({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SystemTimeService>()) {
      return _text('Messenger');
    }
    final service = Get.find<SystemTimeService>();
    return Obx(() {
      service.revision.value;
      final configured = service.appName?.trim() ?? '';
      return _text(configured.isEmpty ? 'Messenger' : configured);
    });
  }

  Widget _text(String value) {
    return Text(
      value,
      textAlign: TextAlign.center,
      style: AppTextStyles.navTitle.copyWith(color: color, fontSize: 24),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo({required this.brandColor});

  final Color brandColor;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SystemTimeService>()) {
      return _fallbackLogo();
    }
    final service = Get.find<SystemTimeService>();
    return Obx(() {
      service.revision.value;
      final url = service.logoUrl?.trim() ?? '';
      if (url.isEmpty) return _fallbackLogo();
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        child: SizedBox(
          width: 64,
          height: 64,
          child: _logoFromUrl(url),
        ),
      );
    });
  }

  Widget _logoFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.svg')) {
      return AirplaneFloat(
        child: SvgPicture.network(
          url,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => _fallbackLogo(),
          errorBuilder: (_, __, ___) => _fallbackLogo(),
        ),
      );
      /*return SvgPicture.network(
        url,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => _fallbackLogo(),
        errorBuilder: (_, __, ___) => _fallbackLogo(),
      );*/
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _fallbackLogo(),
    );
  }

  Widget _fallbackLogo() {
    return SizedBox(
      width: 64,
      height: 64,
      child: SvgPicture.asset(
        'assets/icons/logo_02.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}
