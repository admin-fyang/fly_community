/// 通用圆形头像组件。
///
/// 优先展示网络头像,失败或缺省时回退为「首字母 + 稳定背景色」占位。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/utils/color_util.dart';
import '../../../core/utils/network_image_url_util.dart';
import '../../../data/services/avatar_cache_service.dart';

/// 通用圆形头像
///
/// 优先展示 [imageUrl]，加载失败或为空时回退为「字母 + 稳定背景色」头像。
/// 纯展示组件，不依赖任何 controller。
class AppAvatar extends StatefulWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.name,
    this.size = 48,
    this.backgroundColor,
  });

  final String? imageUrl;

  /// 用于生成字母占位与稳定背景色
  final String? name;
  final double size;

  /// 指定背景色；为空时按 [name] 计算
  final Color? backgroundColor;

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  String? _networkImageUrl;
  Future<Uint8List>? _imageBytes;

  @override
  void initState() {
    super.initState();
    _refreshImageFuture();
  }

  @override
  void didUpdateWidget(covariant AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _refreshImageFuture();
  }

  /// 每个头像 URL 只创建一次文件读取 Future。
  ///
  /// 列表滚动或 GetX 局部刷新会频繁重建 Widget；若在 build 中直接创建 Future，
  /// 即使文件已命中磁盘缓存也会重复触发异步读取并造成占位头像闪烁。
  void _refreshImageFuture() {
    _networkImageUrl = NetworkImageUrlUtil.normalize(widget.imageUrl);
    _imageBytes = _networkImageUrl == null
        ? null
        : AvatarCacheService.bytes(_networkImageUrl!);
  }

  /// 取首字符（中文取首字，英文取前两位首字母）。
  String get _initials {
    final n = (widget.name ?? '').trim();
    if (n.isEmpty) return '?';
    final first = n.characters.first;
    // 英文取前两位首字母更易辨识
    if (RegExp(r'^[A-Za-z]').hasMatch(first)) {
      final parts = n.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return (parts[0].characters.first + parts[1].characters.first)
            .toUpperCase();
      }
      return n.characters.take(2).toString().toUpperCase();
    }
    return first;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _buildFallback();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // 使用物理显示尺寸的 3 倍解码，为缩小显示保留圆周和内部细线的采样。
    // 两端原生对照确认其比 2 倍更接近原始尺寸参考；仍按尺寸缓存，
    // 不将原始分辨率图片直接用于列表。RGBA 缓存约为原 1 倍方案的 9 倍。
    // 保留原有 4096 像素上限；正常 48 dp / DPR 3 头像解码为 432×432。
    final decodeSize = (widget.size * pixelRatio * 3).round().clamp(1, 4096);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _imageBytes != null
          ? FutureBuilder<Uint8List>(
              future: _imageBytes,
              builder: (context, snapshot) => snapshot.hasData
                  ? Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      cacheWidth: decodeSize,
                      cacheHeight: decodeSize,
                      gaplessPlayback: true,
                      // 仅裁剪实际图片；错误回退由 errorBuilder 独立构建，
                      // 避免文字背景再次经过 ClipOval 的圆周采样。
                      frameBuilder: (_, child, __, ___) =>
                          ClipOval(child: child),
                      errorBuilder: (_, __, ___) => fallback,
                    )
                  : fallback,
            )
          : fallback,
    );
  }

  /// 构建字母占位头像(背景色由 name 稳定派生)
  Widget _buildFallback() {
    final bg = widget.backgroundColor ?? ColorUtil.fromText(widget.name ?? '');
    return CustomPaint(
      painter: _AvatarCirclePainter(bg),
      child: Align(
        alignment: Alignment.center,
        child: MediaQuery.withNoTextScaling(
          child: Text(
            _initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.size * 0.38,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 文字头像背景直接画圆，避免先填充矩形再裁剪造成圆周阶梯。
///
/// 文字仍由原有 Text 排版；背景颜色变化时才请求重绘，尺寸变化由
/// CustomPaint 自身处理。图片头像继续使用原有圆形裁剪与过滤等级。
class _AvatarCirclePainter extends CustomPainter {
  const _AvatarCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_AvatarCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
