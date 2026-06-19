import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/core/strings.dart';
import 'package:yeshshree_ops/ui2/data/flow.dart';
import 'package:yeshshree_ops/ui2/nav.dart';
import 'package:yeshshree_ops/ui2/phone_shell.dart';
import 'package:yeshshree_ops/ui2/roles.dart';
import 'package:yeshshree_ops/ui2/theme2.dart';
import 'package:yeshshree_ops/ui2/widgets/frame.dart';

/// Regression for the Phase-3 review's HIGH finding: the process-global Ui2Flow bag
/// leaked context (e.g. a consumed gate.entryId) between the Quality role's
/// independent tabs, which could double-receipt an already-received entry. A tab
/// switch must end the current flow and clear the bag.
void main() {
  testWidgets('switching phone tabs clears ephemeral Ui2Flow state', (tester) async {
    S.lang.value = 'en';
    // A consumed hand-off value lingering in the global flow bag.
    Ui2Flow.set('gate.entryId', 99);

    const tabs = <RoleTab>[
      RoleTab(ScreenId.home, Icons.home, 'TABONE', 'TABONE'),
      RoleTab(ScreenId.tasks, Icons.list, 'TABTWO', 'TABTWO'),
    ];

    await tester.pumpWidget(const ProviderScope(
      child: _Host(child: PhoneShell(tabs: tabs)),
    ));
    // Bounded pumps — several screens run indefinite animations that never settle.
    await tester.pump(const Duration(milliseconds: 400));

    expect(Ui2Flow.get<int>('gate.entryId'), 99,
        reason: 'still set before any tab switch');

    await tester.tap(find.text('TABTWO'));
    await tester.pump();

    expect(Ui2Flow.get<int>('gate.entryId'), isNull,
        reason: 'a tab switch ends the flow and clears the bag');
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: theme2(),
        home: Scaffold(body: Center(child: PhoneFrame2(child: child))),
      );
}
