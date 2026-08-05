import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Surface glassmorphism cohérente avec la DA Arich.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final double blur;
  final Border? border;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.tint,
    this.blur = 22,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final isTizen = Platform.operatingSystem == 'tizen';
    final bg = (tint ?? Colors.white).withOpacity(isTizen ? 0.10 : 0.06);

    Widget inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isTizen ? Colors.black.withOpacity(0.92) : bg,
        borderRadius: radius,
        border: border ?? Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: child,
    );

    if (isTizen) return ClipRRect(borderRadius: radius, child: inner);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: inner,
      ),
    );
  }
}
