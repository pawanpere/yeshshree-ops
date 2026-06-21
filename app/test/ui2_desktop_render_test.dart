import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/core/strings.dart';
import 'package:yeshshree_ops/ui2/nav.dart';
import 'package:yeshshree_ops/ui2/responsive.dart';
import 'package:yeshshree_ops/ui2/screen_registry.dart';
import 'package:yeshshree_ops/ui2/theme2.dart';

/// Desktop-form-factor render coverage (P-R/P-G). The phone-frame stress test
/// only renders screens at 318px; this renders the dual-form-factor screens at a
/// wide desktop size so a desktop-layout overflow can't slip through. Add a
/// screen id here as it gains a bespoke desktop layout.
const _desktopScreens = <ScreenId>[
  ScreenId.gateReceiveItems,
  ScreenId.prodWip,
  // P-R desktop fan-out — every screen given a tailored wide layout.
  ScreenId.gateArrivals,
  ScreenId.qualityWorklist,
  ScreenId.confHistory,
  ScreenId.productionHolds,
  ScreenId.storeStock,
  ScreenId.dispatchList,
  ScreenId.issueHistory,
  ScreenId.notifications,
  ScreenId.tasks,
  ScreenId.sync,
  ScreenId.unmatched,
  ScreenId.planHolds,
  ScreenId.planToday,
  ScreenId.mgmtApprovals,
  ScreenId.mgmtAnomalies,
  ScreenId.adminUsers,
  ScreenId.adminDevices,
  ScreenId.adminMaster,
  ScreenId.vOrders,
  ScreenId.vStock,
  ScreenId.confirmForm,
  ScreenId.issueForm,
  ScreenId.gateMatch,
  ScreenId.gateQc,
  ScreenId.gateGrn,
  ScreenId.offlineGate,
  ScreenId.adminSettings,
  ScreenId.profile,
  ScreenId.cockpit,
  ScreenId.home,
  ScreenId.vHome,
  ScreenId.vFinance,
  ScreenId.dispatchDetail,
  ScreenId.vAlert,
];

class _FakeNav implements PhoneNav {
  @override
  void go(ScreenId id) {}
  @override
  void replace(ScreenId id) {}
  @override
  void pop() {}
  @override
  void tab(int index) {}
  @override
  void home() {}
  @override
  void sheet(SheetId id) {}
  @override
  void closeSheet() {}
  @override
  void overlay(Widget child) {}
  @override
  void hideOverlay() {}
}

bool _isLayoutFailure(String e) {
  if (e.contains('overflowed')) return true;
  final l = e.toLowerCase();
  return l.contains('unbounded') || l.contains('infinite');
}

void main() {
  group('ui2 desktop render', () {
    for (final lang in ['en', 'mr']) {
      testWidgets('dual-form-factor screens render wide in $lang',
          (tester) async {
        S.lang.value = lang;
        // A typical office content area on a 1440 monitor (window − sidebar),
        // capped by ResponsiveContent — comfortably above the desktop breakpoint.
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1320, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final failures = <String>[];
        for (final id in _desktopScreens) {
          final errors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) => errors.add(d.exception.toString());
          try {
            await tester.pumpWidget(ProviderScope(
              child: MaterialApp(
                theme: theme2(),
                home: Scaffold(
                  body: SizedBox(
                    width: BP.maxContent,
                    height: 900,
                    child: buildScreen(id, _FakeNav()),
                  ),
                ),
              ),
            ));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            Object? ex;
            while ((ex = tester.takeException()) != null) {
              errors.add(ex.toString());
            }
          } finally {
            FlutterError.onError = prev;
          }
          final real = errors.where(_isLayoutFailure).toSet().toList();
          if (real.isNotEmpty) failures.add('${id.name}: ${real.join(' | ')}');
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  });
}
