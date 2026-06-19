import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Tiny status glyphs used in list rows / tiles (from the prototype's
/// CSS-shape markers: rotated squares, triangles, rings, dots).
enum GlyphShape { diamond, square, triangle, ring, dot }

class Glyph extends StatelessWidget {
  const Glyph(this.shape, this.color, {super.key, this.size = 10});
  final GlyphShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (shape) {
      case GlyphShape.diamond:
        return Transform.rotate(
          angle: math.pi / 4,
          child: SizedBox(
              width: size, height: size, child: ColoredBox(color: color)),
        );
      case GlyphShape.square:
        return SizedBox(
            width: size, height: size, child: ColoredBox(color: color));
      case GlyphShape.dot:
        return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle));
      case GlyphShape.ring:
        return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2)));
      case GlyphShape.triangle:
        return CustomPaint(
            size: Size(size * 1.1, size), painter: _TrianglePainter(color));
    }
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small status pill (SYNCED / OFFLINE / RUNNING).
class Pill2 extends StatelessWidget {
  const Pill2({
    super.key,
    required this.text,
    required this.fg,
    required this.bg,
    required this.borderColor,
    this.dot = true,
  });
  final String text;
  final Color fg;
  final Color bg;
  final Color borderColor;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(Y2.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(text, style: F.hind(10, w: FontWeight.w600, ls: 0.4, color: fg)),
        ],
      ),
    );
  }
}

/// White rounded card with a 1px hairline border and an optional 4px colored
/// left accent (clipped to the radius). Matches the prototype's row/card shape.
class Card2 extends StatelessWidget {
  const Card2({
    super.key,
    required this.child,
    this.radius = Y2.rCard,
    this.padding = const EdgeInsets.all(13),
    this.onTap,
    this.leftBorder,
    this.bg,
    this.borderColor = Y2.line,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? leftBorder;
  final Color? bg;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final Widget inner = leftBorder == null
        ? Padding(padding: padding, child: child)
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: leftBorder),
                Expanded(child: Padding(padding: padding, child: child)),
              ],
            ),
          );
    final w = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg ?? Y2.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: inner,
    );
    if (onTap == null) return w;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: w);
  }
}
