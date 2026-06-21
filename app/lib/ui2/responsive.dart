import 'package:flutter/widgets.dart';

/// Responsive foundation for the `ui2` layer (P-R).
///
/// Floor/vendor screens were authored for the 336px phone frame; the office
/// roles already had a sidebar desktop shell. This toolkit lets ANY screen ship
/// both a phone and a desktop layout from a single file, so the app adapts
/// phone <-> desktop without duplicating screens.
///
/// IMPORTANT: every decision here is made from the WIDTH OF THE WIDGET'S OWN BOX
/// (via [LayoutBuilder]) — never `MediaQuery`. A phone-shell screen previewed
/// inside the 336px frame on a wide monitor must still see itself as a phone, and
/// only `LayoutBuilder` (local constraints) reports that correctly.
class BP {
  BP._();

  /// Tablet / desktop chrome unlocks here. Matches [OfficeShell]'s existing
  /// sidebar threshold so the two never disagree.
  static const double wide = 820;

  /// True desktop density: 3-up grids, side-by-side master/detail panes.
  static const double desktop = 1200;

  /// Cap for a centered content column so it never stretches edge-to-edge on a
  /// wide monitor.
  static const double maxContent = 1200;
}

enum FormFactor { phone, tablet, desktop }

FormFactor formFactorFor(double width) {
  if (width >= BP.desktop) return FormFactor.desktop;
  if (width >= BP.wide) return FormFactor.tablet;
  return FormFactor.phone;
}

/// Picks a layout by the width of its own box. Provide at least [phone];
/// [tablet]/[desktop] fall back to the next builder when omitted, so a screen
/// can adopt a desktop layout incrementally without breaking its phone view.
class Responsive extends StatelessWidget {
  const Responsive({
    super.key,
    required this.phone,
    this.tablet,
    this.desktop,
  });

  final WidgetBuilder phone;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      switch (formFactorFor(c.maxWidth)) {
        case FormFactor.desktop:
          return (desktop ?? tablet ?? phone)(context);
        case FormFactor.tablet:
          return (tablet ?? desktop ?? phone)(context);
        case FormFactor.phone:
          return phone(context);
      }
    });
  }
}

/// Boolean builder for the common phone-vs-wide split, when a full [Responsive]
/// three-way split is overkill.
class WideBuilder extends StatelessWidget {
  const WideBuilder(this.builder, {super.key});
  final Widget Function(BuildContext context, bool wide) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => builder(context, c.maxWidth >= BP.wide),
      );
}

/// Caps the child's width on wide viewports (centered) while PRESERVING the
/// incoming height contract — so it is safe to wrap a full-height screen that
/// uses `Expanded`/`ListView`. On a box already narrower than [maxWidth] (the
/// phone frame, a narrow window) it is a pure pass-through.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = BP.maxContent,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth <= maxWidth) return child;
      // Keep height tight when the parent gave a bounded height (shell content
      // area) so inner `Expanded`/`ListView` still work; let the child size
      // itself when height is unbounded (inside a scroll view).
      final h = c.maxHeight.isFinite ? c.maxHeight : null;
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: maxWidth, height: h, child: child),
      );
    });
  }
}

/// A responsive tile grid: as many equal columns as fit at [minTileWidth],
/// clamped to [maxColumns]; a single stacked column below [BP.wide] (phone).
/// Children must be self-sizing in height.
class CardGrid2 extends StatelessWidget {
  const CardGrid2({
    super.key,
    required this.children,
    this.minTileWidth = 320,
    this.maxColumns = 4,
    this.gap = 14,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      var cols = w < BP.wide ? 1 : (w / (minTileWidth + gap)).floor();
      cols = cols.clamp(1, maxColumns);
      if (cols <= 1) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      }
      final tileW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final ch in children) SizedBox(width: tileW, child: ch),
        ],
      );
    });
  }
}
