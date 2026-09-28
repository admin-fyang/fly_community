/// Grouped surface used by settings/profile style screens.
///
/// It deliberately avoids elevation. Hierarchy comes from the cool grouped
/// page canvas, a clean surface and a one-physical-pixel separator.
library;

import 'package:flutter/material.dart';

import '../../core/extensions/context_extension.dart';
import '../../core/theme/app_sizes.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.children = const [],
    this.child,
    this.backgroundColor,
    this.borderRadius = AppSizes.radiusGrouped,
    this.border,
    this.boxShadow = const [],
    this.dividerColor,
    this.dividerIndent = 0,
    this.dividerEndIndent = 0,
  }) : assert(child == null || children.length == 0);

  final List<Widget> children;
  final Widget? child;
  final Color? backgroundColor;
  final double borderRadius;
  final BoxBorder? border;
  final List<BoxShadow> boxShadow;
  final Color? dividerColor;
  final double dividerIndent;
  final double dividerEndIndent;

  @override
  Widget build(BuildContext context) {
    final sourceChildren = child == null ? children : <Widget>[child!];
    final divided = <Widget>[];
    for (var i = 0; i < sourceChildren.length; i++) {
      if (i > 0) {
        divided.add(
          _PhysicalHairline(
            color: dividerColor ?? context.semanticColors.separator,
            indent: dividerIndent,
            endIndent: dividerEndIndent,
          ),
        );
      }
      divided.add(sourceChildren[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? context.semanticColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: divided),
        ),
      ),
    );
  }
}

class _PhysicalHairline extends StatelessWidget {
  const _PhysicalHairline({
    required this.color,
    required this.indent,
    required this.endIndent,
  });

  final Color color;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final thickness = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: thickness,
        child: ColoredBox(color: color),
      ),
    );
  }
}
