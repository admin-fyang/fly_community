/// 地区号选择组件。
///
/// 只维护客户端展示所需的地区码和拨号码；提交接口时使用 [RegionCodeOption.regionCode]。
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_text_styles.dart';
import 'interaction/app_pressable.dart';
import 'overlay/app_action_sheet.dart';

class RegionCodeOption {
  const RegionCodeOption({
    required this.regionCode,
    required this.dialCode,
    required this.name,
  });

  /// API 字段 region_code 使用的稳定地区码，例如 CN、HK、US。
  final String regionCode;

  /// 给用户看的国际电话区号。
  final String dialCode;

  final String name;

  String get label => '$dialCode $name';

  static const all = <RegionCodeOption>[
    RegionCodeOption(regionCode: 'CN', dialCode: '+86', name: '中国大陆'),
    RegionCodeOption(regionCode: 'HK', dialCode: '+852', name: '中国香港'),
    RegionCodeOption(regionCode: 'MO', dialCode: '+853', name: '中国澳门'),
    RegionCodeOption(regionCode: 'TW', dialCode: '+886', name: '中国台湾'),
    RegionCodeOption(regionCode: 'US', dialCode: '+1', name: '美国/加拿大'),
    RegionCodeOption(regionCode: 'SG', dialCode: '+65', name: '新加坡'),
    RegionCodeOption(regionCode: 'JP', dialCode: '+81', name: '日本'),
    RegionCodeOption(regionCode: 'KR', dialCode: '+82', name: '韩国'),
  ];

  static RegionCodeOption byCode(String? code) {
    return all.firstWhereOrNull((item) => item.regionCode == code) ?? all.first;
  }


}

class RegionCodePickerButton extends StatelessWidget {
  const RegionCodePickerButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final option = RegionCodeOption.byCode(value);
    return AppPressable(
      semanticLabel: option.label,
      onTap: () => _showPicker(context),
      pressedColor: context.semanticColors.surfacePressed,
      borderRadius: BorderRadius.circular(AppSizes.radiusDefault),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSizes.paddingSm : AppSizes.paddingMd,
          vertical: compact ? AppSizes.paddingXs : AppSizes.paddingSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.dialCode,
              style: AppTextStyles.messageBody.copyWith(
                color: context.semanticColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSizes.paddingXs),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: context.semanticColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final selected = await showAppActionSheet<RegionCodeOption>(
      context,
      title: '国家和地区',
      items: [
        for (final option in RegionCodeOption.all)
          AppActionSheetItem<RegionCodeOption>(
            value: option,
            title: option.name,
            subtitle: option.regionCode,
            trailingText: option.dialCode,
            selected: option.regionCode == value,
          ),
      ],
    );
    if (selected != null && selected.regionCode != value) {
      onChanged(selected.regionCode);
    }
  }
}
