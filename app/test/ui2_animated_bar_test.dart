import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/theme2.dart';
import 'package:yeshshree_ops/ui2/widgets/polish2.dart';

/// Regression: AnimatedBar2 must render a VISIBLE fill (non-zero height + a width
/// proportional to the fraction). The bug was a FractionallySizedBox with no
/// heightFactor, which collapsed the fill to 0 px tall so every % bar looked empty.
void main() {
  testWidgets('AnimatedBar2 fill fills the height and scales with the fraction',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme2(),
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: AnimatedBar2(fraction: 0.5, height: 12),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800)); // past the 700ms tween

    final fillFinder = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(ColoredBox),
    );
    final fill = tester.getSize(fillFinder);
    expect(fill.height, greaterThan(0), reason: 'fill must be full height, not 0');
    // 50% of the ~200px track (minus the 1px border on each side).
    expect(fill.width, greaterThan(80));
    expect(fill.width, lessThan(120));
  });

  testWidgets('AnimatedBar2 with fraction 0 has an (near-)empty fill',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, child: AnimatedBar2(fraction: 0)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    final fillFinder = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(ColoredBox),
    );
    expect(tester.getSize(fillFinder).width, lessThan(1));
  });
}
