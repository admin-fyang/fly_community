import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/log_util.dart';
import 'system_time_service.dart';

/// 将系统配置下发的品牌 Logo 缓存为 Android 通知可读取的本地位图。
///
/// Android 状态栏 small icon 必须是 APK 内置 drawable，网络 Logo 只能作为
/// 通知卡片的 large icon 使用。当前后端 Logo 允许 SVG，因此这里会先栅格化为 PNG。
class NotificationBrandingService {
  NotificationBrandingService(this._systemConfig, {Dio? dio})
    : _dio = dio ?? Dio();

  static const _urlKey = 'notification.brand_logo_url';
  static const _pathKey = 'notification.brand_logo_path';
  static const _fileName = 'notification_brand_logo.png';
  static const _targetSize = 192;

  final SystemTimeService _systemConfig;
  final Dio _dio;

  Future<String?>? _refreshTask;

  Future<String?> resolveLargeIconPath() => refresh();

  Future<String?> refresh() {
    final running = _refreshTask;
    if (running != null) return running;
    final task = _refresh();
    _refreshTask = task;
    task.whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    }).ignore();
    return task;
  }

  Future<String?> _refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final rawUrl = _systemConfig.logoUrl?.trim() ?? '';
    if (rawUrl.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final cachedUrl = prefs.getString(_urlKey)?.trim() ?? '';
    final cachedPath = prefs.getString(_pathKey)?.trim() ?? '';
    if (cachedUrl == rawUrl && cachedPath.isNotEmpty) {
      final file = File(cachedPath);
      if (await file.exists() && await file.length() > 0) return cachedPath;
    }

    try {
      final response = await _dio.get<List<int>>(
        rawUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      final bytes = Uint8List.fromList(data);
      final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
      final output = _looksLikeSvg(rawUrl, contentType, bytes)
          ? await _svgToPng(bytes)
          : await _rasterToPng(bytes);
      if (output == null || output.isEmpty) return null;

      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$_fileName');
      await file.writeAsBytes(output, flush: true);
      await prefs.setString(_urlKey, rawUrl);
      await prefs.setString(_pathKey, file.path);
      return file.path;
    } catch (error) {
      LogUtil.d('logo-cache-failed error=$error', tag: 'Notification branding');
      return null;
    }
  }

  static Future<String?> readCachedLargeIconPath({String? expectedUrl}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final cachedUrl = prefs.getString(_urlKey)?.trim() ?? '';
      if (expectedUrl != null) {
        final wanted = expectedUrl.trim();
        if (wanted.isEmpty || cachedUrl != wanted) return null;
      }
      final path = prefs.getString(_pathKey)?.trim() ?? '';
      if (path.isEmpty) return null;
      final file = File(path);
      return await file.exists() && await file.length() > 0 ? path : null;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeSvg(
    String url,
    String contentType,
    Uint8List bytes,
  ) {
    if (Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') == true) {
      return true;
    }
    if (contentType.toLowerCase().contains('svg')) return true;
    final prefixLength = math.min(bytes.length, 256);
    final prefix = utf8
        .decode(bytes.sublist(0, prefixLength), allowMalformed: true)
        .toLowerCase();
    return prefix.contains('<svg');
  }

  static Future<Uint8List?> _svgToPng(Uint8List bytes) async {
    final rawSvg = utf8.decode(bytes, allowMalformed: true);
    final pictureInfo = await vg.loadPicture(SvgStringLoader(rawSvg), null);
    try {
      final sourceSize = pictureInfo.size;
      if (sourceSize.width <= 0 || sourceSize.height <= 0) return null;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final scale = math.min(
        _targetSize / sourceSize.width,
        _targetSize / sourceSize.height,
      );
      final dx = (_targetSize - sourceSize.width * scale) / 2;
      final dy = (_targetSize - sourceSize.height * scale) / 2;
      canvas.translate(dx, dy);
      canvas.scale(scale);
      canvas.drawPicture(pictureInfo.picture);
      final rasterPicture = recorder.endRecording();
      final image = await rasterPicture.toImage(_targetSize, _targetSize);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  static Future<Uint8List?> _rasterToPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final source = ui.Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
        final scale = math.min(
          _targetSize / image.width,
          _targetSize / image.height,
        );
        final width = image.width * scale;
        final height = image.height * scale;
        final target = ui.Rect.fromLTWH(
          (_targetSize - width) / 2,
          (_targetSize - height) / 2,
          width,
          height,
        );
        canvas.drawImageRect(image, source, target, ui.Paint());
        final rasterPicture = recorder.endRecording();
        final output = await rasterPicture.toImage(_targetSize, _targetSize);
        try {
          final data = await output.toByteData(format: ui.ImageByteFormat.png);
          return data?.buffer.asUint8List();
        } finally {
          output.dispose();
        }
      } finally {
        image.dispose();
      }
    } catch (error) {
      debugPrint('[Notification branding] raster decode failed: $error');
      return null;
    } finally {
      codec.dispose();
    }
  }
}
