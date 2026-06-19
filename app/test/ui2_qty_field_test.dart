import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/widgets/qty_field2.dart';

/// QtyField2 is the typed-editable quantity input that replaced the read-only
/// stepper counts (Phase 1b) — an operator can type "215" instead of tapping +.
void main() {
  Widget host({num value = 0, num max = 99999, bool decimal = false,
      required ValueChanged<num> onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: QtyField2(
            value: value, max: max, decimal: decimal, onChanged: onChanged),
      ),
    );
  }

  testWidgets('typing a number reports it via onChanged', (tester) async {
    num? captured;
    await tester.pumpWidget(host(onChanged: (v) => captured = v));
    await tester.enterText(find.byType(TextField), '215');
    await tester.pump();
    expect(captured, 215);
  });

  testWidgets('letters are filtered out of an integer field', (tester) async {
    num? captured;
    await tester.pumpWidget(host(onChanged: (v) => captured = v));
    await tester.enterText(find.byType(TextField), '2a1b5');
    await tester.pump();
    expect(captured, 215);
  });

  testWidgets('value is clamped to max', (tester) async {
    num? captured;
    await tester.pumpWidget(host(max: 100, onChanged: (v) => captured = v));
    await tester.enterText(find.byType(TextField), '500');
    await tester.pump();
    expect(captured, 100);
  });

  testWidgets('clearing the field falls back to the floor (0)', (tester) async {
    num? captured;
    await tester.pumpWidget(host(value: 9, onChanged: (v) => captured = v));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(captured, 0);
  });

  testWidgets('decimal field accepts a decimal point', (tester) async {
    num? captured;
    await tester.pumpWidget(host(decimal: true, onChanged: (v) => captured = v));
    await tester.enterText(find.byType(TextField), '12.5');
    await tester.pump();
    expect(captured, 12.5);
  });
}
