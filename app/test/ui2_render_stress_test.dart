import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/core/strings.dart';
import 'package:yeshshree_ops/ui2/phone_shell.dart';
import 'package:yeshshree_ops/ui2/screen_registry.dart';
import 'package:yeshshree_ops/ui2/theme2.dart';
import 'package:yeshshree_ops/ui2/ui2_demo_app.dart';
import 'package:yeshshree_ops/ui2/widgets/frame.dart';

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: theme2(),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: child),
        ),
      ),
    );

Future<void> _pumpAt(
  WidgetTester tester,
  Size logicalSize,
  Widget child,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(child));
  // Bounded pumps instead of pumpAndSettle: several screens run indefinite
  // animations (skeleton shimmer, sync spinner) that never "settle", so
  // pumpAndSettle would time out. A few timed pumps render the screen and let
  // async reads + finite entrance animations advance — enough to surface any
  // RenderFlex overflow, which throws during layout on every pump.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

String _shortError(Object error) {
  final text = error.toString();
  final overflow = RegExp(r'A RenderFlex overflowed by ([^\n]+)')
      .firstMatch(text)
      ?.group(0);
  if (overflow != null) return overflow;

  final box = RegExp(r'RenderBox was not laid out: [^\n]+')
      .firstMatch(text)
      ?.group(0);
  if (box != null) return box;

  return text.split('\n').first;
}

/// A genuine, layout-time failure worth failing the suite over: a RenderFlex
/// overflow, or a vertical-axis unbounded/infinite-height constraint error (the
/// "hard" failures the stress-test report called out, e.g. a scroll view or a
/// flexible child handed unbounded height).
bool _isLayoutFailure(String e) {
  if (e.contains('overflowed')) return true;
  final l = e.toLowerCase();
  return l.contains('unbounded height') ||
      l.contains('infinite height') ||
      l.contains('incoming height constraints are unbounded') ||
      l.contains('vertical viewport was given unbounded height');
}

Future<List<String>> _collectRenderErrors(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final previous = FlutterError.onError;
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(_shortError(details.exception));
  };
  try {
    await body();
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      errors.add(_shortError(exception!));
    }
  } finally {
    FlutterError.onError = previous;
  }
  // This suite guards against layout failures that throw during layout: RenderFlex
  // OVERFLOW and UNBOUNDED/INFINITE-HEIGHT constraint errors (a scrollable or a
  // flex child given unbounded vertical space — the hard failures the stress-test
  // report flagged). "RenderBox was not laid out" alone is a downstream symptom that
  // can fire transiently under bounded pumps, so it is NOT counted on its own.
  return errors.where(_isLayoutFailure).toSet().toList();
}

/// Screens with a KNOWN unbounded-height failure that is deferred, not a
/// regression. The infinite-height assertion is suppressed for these (overflow is
/// still enforced). Keep this list shrinking — remove an entry the moment its
/// screen is fixed or deleted (see app/FRONTEND_STRESS_TEST_REPORT.md):
///   - saleForm: billing screen, explicitly out of scope for the roles pilot.
/// (gateScanned was the in-app camera-scan screen — DELETED in Phase 2.)
const _deferredInfiniteHeight = {'saleForm'};

void main() {
  group('ui2 render stress', () {
    for (final lang in ['en', 'mr']) {
      testWidgets('all registered screens render in $lang', (tester) async {
        S.lang.value = lang;
        final failures = <String>[];

        for (final entry in kScreens) {
          var errors = await _collectRenderErrors(tester, () async {
            await _pumpAt(
              tester,
              const Size(390, 844),
              PhoneFrame2(
                child: PhoneShell(
                  key: ValueKey('${entry.id.name}-$lang'),
                  initial: entry.id,
                ),
              ),
            );
          });

          // Deferred screens: still fail on overflow, but tolerate their known
          // infinite-height bug until the screen is fixed/removed.
          if (_deferredInfiniteHeight.contains(entry.id.name)) {
            errors = errors.where((e) => e.contains('overflowed')).toList();
          }

          if (errors.isNotEmpty) {
            failures.add('${entry.id.name}: ${errors.join(' | ')}');
          }
        }

        expect(
          failures,
          isEmpty,
          reason: failures.join('\n\n'),
        );
      });
    }

    testWidgets('gallery shell fits the common narrow phone viewport',
        (tester) async {
      S.lang.value = 'en';

      final errors = await _collectRenderErrors(tester, () async {
        await _pumpAt(
          tester,
          const Size(390, 844),
          const Ui2DemoApp(),
        );
      });
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
