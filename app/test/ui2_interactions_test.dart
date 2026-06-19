import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/nav.dart';
import 'package:yeshshree_ops/ui2/screens/confirm_form_screen.dart';
import 'package:yeshshree_ops/ui2/screens/tasks_screen.dart';

/// Records navigation calls so tests can assert flow behavior.
class _RecNav implements PhoneNav {
  final calls = <String>[];
  Widget? lastOverlay;
  @override
  void go(ScreenId id) => calls.add('go:${id.name}');
  @override
  void replace(ScreenId id) => calls.add('replace:${id.name}');
  @override
  void pop() => calls.add('pop');
  @override
  void tab(int index) => calls.add('tab:$index');
  @override
  void home() => calls.add('home');
  @override
  void sheet(SheetId id) => calls.add('sheet:${id.name}');
  @override
  void closeSheet() => calls.add('closeSheet');
  @override
  void overlay(Widget child) {
    lastOverlay = child;
    calls.add('overlay');
  }

  @override
  void hideOverlay() => calls.add('hideOverlay');
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('confirm form: quick-add steppers change the good count', (t) async {
    final nav = _RecNav();
    await t.pumpWidget(_host(Ui2ConfirmFormScreen(nav: nav)));

    await t.tap(find.text('+10'));
    await t.pump();
    await t.tap(find.text('+5'));
    await t.pump();

    // good = 15 shown in the big mono number.
    expect(find.text('15'), findsOneWidget);
    // after-post preview (a Text.rich span) reflects 120 + 15 = 135.
    expect(
      find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('135/200')),
      findsOneWidget,
    );
  });

  testWidgets('confirm form: submitting advances to the syncing screen', (t) async {
    final nav = _RecNav();
    await t.pumpWidget(_host(Ui2ConfirmFormScreen(nav: nav)));

    await t.tap(find.text('+10'));
    await t.pump();
    await t.tap(find.text('Close shift'));
    await t.pump();

    expect(nav.calls, contains('replace:confirmSyncing'));
  });

  testWidgets('confirm form: submitting with zero good is blocked', (t) async {
    final nav = _RecNav();
    await t.pumpWidget(_host(Ui2ConfirmFormScreen(nav: nav)));

    await t.tap(find.text('Close shift'));
    await t.pump();

    // No navigation — validation stopped it.
    expect(nav.calls.where((c) => c.startsWith('replace')), isEmpty);
  });

  testWidgets('tasks: Mine filter narrows the list to the user\'s tasks',
      (t) async {
    final nav = _RecNav();
    await t.pumpWidget(_host(Ui2TasksScreen(nav: nav)));

    // All (default) shows a non-mine task.
    expect(find.text('Receipt to check'), findsOneWidget);
    expect(find.text('Approval waiting'), findsOneWidget);

    await t.tap(find.textContaining('Mine'));
    await t.pump();

    // 'Receipt to check' is not a "mine" task → filtered out.
    expect(find.text('Receipt to check'), findsNothing);
    // 'Approval waiting' is mine → still shown.
    expect(find.text('Approval waiting'), findsOneWidget);
  });

  testWidgets('tasks: tapping a row navigates', (t) async {
    final nav = _RecNav();
    await t.pumpWidget(_host(Ui2TasksScreen(nav: nav)));

    await t.tap(find.text('Unmatched vehicle'));
    await t.pump();

    expect(nav.calls, contains('go:unmatched'));
  });
}
