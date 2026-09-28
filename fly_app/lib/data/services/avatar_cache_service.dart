/// 与消息媒体缓存隔离的头像文件缓存。
library;

import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AvatarCacheService {
  AvatarCacheService._();

  static final CacheManager _manager = CacheManager(
    Config(
      'chat_fly_directory_avatar_v1',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );

  static Future<Uint8List> bytes(String url) async =>
      (await _manager.getSingleFile(url)).readAsBytes();

  static Future<void> empty() => _manager.emptyCache();
}
