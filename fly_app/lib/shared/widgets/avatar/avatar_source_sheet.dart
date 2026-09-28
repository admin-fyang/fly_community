/// 头像来源选择弹层。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/avatar_picker_service.dart';
import '../overlay/app_action_sheet.dart';

Future<AvatarPickSource?> showAvatarPickSourceSheet(BuildContext context) {
  final supportsCamera =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return showAppActionSheet<AvatarPickSource>(
    context,
    title: '更换头像',
    items: [
      if (supportsCamera)
        const AppActionSheetItem<AvatarPickSource>(
          value: AvatarPickSource.camera,
          title: '拍照',
          icon: Icons.photo_camera_outlined,
        ),
      AppActionSheetItem<AvatarPickSource>(
        value: AvatarPickSource.gallery,
        title: supportsCamera ? '从相册选择' : '选择图片文件',
        icon: Icons.photo_library_outlined,
      ),
    ],
  );
}
