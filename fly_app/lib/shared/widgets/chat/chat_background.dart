/// Unified chat wallpaper renderer.
///
/// Wallpaper is treated as an environmental layer: a muted base, low-intensity
/// pattern and subtle veil. Message bubbles stay visually dominant even when a
/// decorative wallpaper is selected.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../data/local/app_settings_storage.dart';

class ChatBackground extends StatelessWidget {
  const ChatBackground({required this.background, this.child, super.key});

  final ChatBackgroundType background;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.chatWallpaperTokens;

    return ColoredBox(
      color: wallpaper.base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: IgnorePointer(
              child: _pattern(context),
            ),
          ),
          // The veil compresses wallpaper contrast without dimming message
          // bubbles, because it is rendered below the chat content layer.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [wallpaper.veilTop, wallpaper.veilBottom],
                ),
              ),
            ),
          ),
          if (child case final value?) value,
        ],
      ),
    );
  }

  Widget _pattern(BuildContext context) {
    final wallpaper = context.chatWallpaperTokens;
    return switch (background) {
      ChatBackgroundType.patternSvg => Opacity(
        opacity: wallpaper.patternOpacity,
        child: SvgPicture.asset(
          background.assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.topLeft,
          colorFilter: ColorFilter.mode(
            wallpaper.patternTint,
            BlendMode.srcIn,
          ),
        ),
      ),
      ChatBackgroundType.patternPng => Opacity(
        opacity: wallpaper.rasterOpacity,
        child: Image.asset(
          background.assetPath,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topLeft,
          color: wallpaper.patternTint,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.low,
        ),
      ),
    };
  }
}
