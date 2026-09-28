/// 设备页的 PC 扫码登录入口；仅渲染说明与插画，点击行为由页面提供。
library;

import 'package:flutter/material.dart';

import '../../../core/extensions/context_extension.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/section_card.dart';

class DeviceLinkCard extends StatelessWidget {
  const DeviceLinkCard({super.key, required this.onAddDevice});

  final VoidCallback onAddDevice;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    return SectionCard(
      borderRadius: 16,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Center(
                child: CustomPaint(
                  size: const Size(140, 112),
                  painter: _LaptopPainter(accent: colors.accent),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '扫描二维码以登录 '),
                  TextSpan(
                    text: 'PC 端',
                    style: TextStyle(color: colors.accent),
                  ),
                  const TextSpan(text: '。'),
                ],
              ),
              textAlign: TextAlign.center,
              style: AppTextStyles.listTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAddDevice,
              style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.primary,
                foregroundColor: context.colorScheme.onPrimary,
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, size: 22),
                  SizedBox(width: 8),
                  Flexible(child: Text('添加设备', textAlign: TextAlign.center)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 用矢量绘制笔记本及聊天窗口，避免引入图片依赖，缩放时保持清晰。
class _LaptopPainter extends CustomPainter {
  const _LaptopPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 140, size.height / 112);
    final paint = Paint();
    void box(Rect rect, Color color, [double radius = 2]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint..color = color,
      );
    }

    // 插画硬件使用固定金属色，屏幕强调色随主题变化。
    box(const Rect.fromLTWH(15, 2, 110, 76), const Color(0xFF9DA6B1), 5);
    box(const Rect.fromLTWH(18, 5, 104, 70), const Color(0xFF26333F), 3);
    box(const Rect.fromLTWH(22, 9, 96, 61), const Color(0xFFEAF1F5), 1);
    box(const Rect.fromLTWH(23, 10, 30, 59), Colors.white, 0);
    box(const Rect.fromLTWH(56, 13, 57, 4), const Color(0xFFBAC8D2));
    for (var row = 0; row < 5; row++) {
      final y = 17.0 + row * 10;
      canvas.drawCircle(Offset(28, y), 3, paint..color = accent);
      box(Rect.fromLTWH(34, y - 2, 15, 2), const Color(0xFF9AAAB6));
      box(Rect.fromLTWH(34, y + 2, 10, 1.5), const Color(0xFFD0DAE1));
    }
    for (var row = 0; row < 3; row++) {
      final y = 23.0 + row * 14;
      box(
        Rect.fromLTWH(row.isEven ? 58 : 73, y, 37, 10),
        row.isEven ? Colors.white : accent.withValues(alpha: 0.45),
        3,
      );
      box(
        Rect.fromLTWH(row.isEven ? 62 : 77, y + 4, 25, 2),
        const Color(0xFF8096A5),
      );
    }
    final base = Path()
      ..moveTo(15, 77)
      ..lineTo(125, 77)
      ..lineTo(139, 106)
      ..quadraticBezierTo(140, 110, 135, 110)
      ..lineTo(5, 110)
      ..quadraticBezierTo(0, 110, 1, 106)
      ..close();
    canvas.drawPath(base, paint..color = const Color(0xFFBBC2CC));
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 11; column++) {
        box(
          Rect.fromLTWH(19 + column * 9.0 - row, 81 + row * 5.0, 7, 3.5),
          const Color(0xFF34424F),
          0.7,
        );
      }
    }
    box(const Rect.fromLTWH(51, 98, 38, 9), const Color(0xFF969FAC));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaptopPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
