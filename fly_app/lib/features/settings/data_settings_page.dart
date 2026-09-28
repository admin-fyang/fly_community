/// 数据和存储设置页。
///
/// 社区版只提供实际可用的图片缓存清理功能。
library;

import 'package:flutter/material.dart';
import 'package:flychat/shared/widgets/loading/app_loading_indicator.dart';
import 'package:get/get.dart';

import '../../data/services/image_cache_service.dart';
import '../../shared/utils/app_toast.dart';
import '../../shared/widgets/section_card.dart';
import 'widgets/settings_scaffold.dart';
import 'widgets/settings_tile.dart';

/// 数据和存储设置。
class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({super.key});

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  bool _clearingCache = false;

  Future<void> _clearLocalCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      await Get.find<ImageCacheService>().clear();
      AppToast.success('图片缓存已清理');
    } catch (_) {
      AppToast.error('缓存清理失败，请重试');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '数据和存储',
      children: [
        SectionCard(
          children: [
            SettingsTile(
              icon: Icons.pie_chart_outline,
              title: '图片缓存',
              subtitle: _clearingCache ? '正在清理图片缓存…' : '清理本地图片缓存',
              trailing: _clearingCache
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppLoadingIndicator(size: 18),
                    )
                  : null,
              onTap: _clearLocalCache,
            ),
          ],
        ),
      ],
    );
  }
}
