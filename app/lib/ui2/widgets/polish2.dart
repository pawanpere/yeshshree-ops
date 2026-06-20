import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../tokens.dart';
import 'icons2.dart';

// ---------------------------------------------------------------------------
// Pressable wrapper — scale + haptic on press, for any tappable surface.
// ---------------------------------------------------------------------------
class Pressable2 extends StatefulWidget {
  const Pressable2({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable2> createState() => _Pressable2State();
}

class _Pressable2State extends State<Pressable2> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _set(true);
        if (widget.haptic && widget.onTap != null) {
          HapticFeedback.selectionClick();
        }
      },
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary CTA — pressed + busy (spinner) + disabled states.
// ---------------------------------------------------------------------------
class PrimaryButton2 extends StatelessWidget {
  const PrimaryButton2({
    super.key,
    required this.label,
    this.onTap,
    this.busy = false,
    this.enabled = true,
    this.color = Y2.accent,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool enabled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !busy;
    return Pressable2(
      onTap: active ? onTap : null,
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.all(14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(label,
                        style:
                            F.hind(15, w: FontWeight.w600, color: Colors.white)),
                  ],
                )
              : Text(label,
                  style: F.hind(15, w: FontWeight.w600, color: Colors.white)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outline / secondary button.
// ---------------------------------------------------------------------------
class OutlineButton2 extends StatelessWidget {
  const OutlineButton2({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable2(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCDD6E3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared drill-down header — back affordance (44px hit target) + title.
// ---------------------------------------------------------------------------
class ScreenHeader2 extends StatelessWidget {
  const ScreenHeader2({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.subtitle,
    this.chip,
    this.demo = false,
  });
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String? subtitle;
  final Widget? chip; // small leading chip (e.g. a doc code)
  final bool demo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Y2.line))),
      child: Row(
        children: [
          if (onBack != null) BackButton2(onTap: onBack!) else const SizedBox(width: 8),
          if (chip != null) ...[chip!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: F.khand(17, ls: 0.3, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      style: F.hind(11, color: Y2.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (demo) const DemoChip(),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class BackButton2 extends StatelessWidget {
  const BackButton2({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable2(
      haptic: false,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD2DAE6)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(I2.back, size: 22, color: Y2.muted),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "DEMO DATA" marker chip.
// ---------------------------------------------------------------------------
class DemoChip extends StatelessWidget {
  const DemoChip({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Y2.orangeTint,
        border: Border.all(color: Y2.orangeLine),
        borderRadius: BorderRadius.circular(Y2.rPill),
      ),
      child: Text(S.t('DEMO DATA', 'डेमो डेटा'),
          style: F.hind(9, w: FontWeight.w600, ls: 0.5, color: Y2.orange)),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — centered icon + title + subtitle (+ optional action).
// ---------------------------------------------------------------------------
class EmptyState2 extends StatelessWidget {
  const EmptyState2({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Y2.lineSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: Y2.muted2),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: F.khand(18, ls: 0.2, color: Y2.ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: F.hind(12, color: Y2.muted, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton — pulsing grey block + a ready-made list of skeleton rows.
// ---------------------------------------------------------------------------
class Skeleton2 extends StatefulWidget {
  const Skeleton2(
      {super.key, this.width = double.infinity, this.height = 14, this.radius = 6});
  final double width;
  final double height;
  final double radius;

  @override
  State<Skeleton2> createState() => _Skeleton2State();
}

class _Skeleton2State extends State<Skeleton2>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.45 + 0.35 * _c.value,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Y2.lineSoft,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Skeleton2(width: 150, height: 13),
            SizedBox(height: 8),
            Skeleton2(width: 90, height: 11),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated progress bar — tweens its fill on mount.
// ---------------------------------------------------------------------------
class AnimatedBar2 extends StatelessWidget {
  const AnimatedBar2(
      {super.key,
      required this.fraction,
      this.height = 9,
      this.color = Y2.accent});
  final double fraction;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Y2.lineSoft,
        border: Border.all(color: Y2.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Number ticker — counts from 0 to value on mount.
// ---------------------------------------------------------------------------
class Ticker2 extends StatelessWidget {
  const Ticker2(this.value, {super.key, required this.style, this.suffix = ''});
  final int value;
  final TextStyle style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}$suffix', style: style),
    );
  }
}

// ---------------------------------------------------------------------------
// Sparkline — a small trend polyline from a list of readings.
// ---------------------------------------------------------------------------
class Sparkline2 extends StatelessWidget {
  const Sparkline2(this.points,
      {super.key, this.width = 64, this.height = 22, this.color = Y2.accent});
  final List<double> points;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparkPainter(points, color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final lo = points.reduce((a, b) => a < b ? a : b);
    final hi = points.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    final dx = size.width / (points.length - 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = dx * i;
      final y = size.height - ((points[i] - lo) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.points != points;
}
