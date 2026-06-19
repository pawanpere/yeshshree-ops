# Frontend Stress Test Report

Date: 2026-06-19  
App path: `/Users/pawanpere/yeshshree-ops/app`  
Target: Flutter UI2 frontend, production web build with `--dart-define=UI2_MODE=true`

## Executive Summary

I found real frontend bugs. The current UI2 prototype builds and its existing interaction tests pass, but render stress testing exposes widespread layout failures inside the fixed 336 x 706 phone frame.

The most important failures are:

- `gateScanned` and `saleForm` can hit hard layout failures from unbounded height constraints, not just cosmetic overflow.
- 21 registered UI2 screens have horizontal or vertical `RenderFlex` overflow in at least one language.
- The Home screen, which is the first visible screen, overflows in both English and Marathi.
- The production web bundle boots and serves assets, but Flutter canvas rendering makes browser DOM inspection thin; the repeatable Flutter render stress test is the stronger evidence source.

## Test Coverage Run

Commands run:

```bash
/Users/pawanpere/flutter-sdk/bin/flutter --version
/Users/pawanpere/flutter-sdk/bin/flutter analyze
/Users/pawanpere/flutter-sdk/bin/flutter test test/ui2_interactions_test.dart
/Users/pawanpere/flutter-sdk/bin/flutter build web --release --dart-define=UI2_MODE=true
/Users/pawanpere/flutter-sdk/bin/flutter test test/ui2_render_stress_test.dart
python3 -m http.server 9187 --directory build/web
curl -I --max-time 5 http://localhost:9187/
```

Results:

| Check | Result | Notes |
|---|---:|---|
| Flutter SDK | Pass | Flutter 3.44.2, Dart 3.12.2 at `/Users/pawanpere/flutter-sdk/bin/flutter`. |
| Static analysis | Pass | `flutter analyze` reports no issues. |
| Existing interactions | Pass | `test/ui2_interactions_test.dart`: 5 tests passed. |
| Production web build | Pass | `flutter build web --release --dart-define=UI2_MODE=true` completed. |
| Static web serving | Pass | `curl -I http://localhost:9187/` returned HTTP 200. |
| Browser startup sanity | Pass with caveat | Production bundle opened as `Yeshshree Ops · ui2`; startup console was clean. Browser screenshot capture later timed out at the tooling layer. |
| Render stress sweep | Fail | `test/ui2_render_stress_test.dart` found layout errors across EN/MR screen renders. |

## Findings

### P1: Hard layout failures in scan and sale forms

Screens:

- `gateScanned`
- `saleForm`

Evidence:

- `gateScanned`: `BoxConstraints forces an infinite height`, followed by cascading `RenderBox was not laid out` failures.
- `saleForm`: same unbounded-height pattern, plus a 105 px EN and 157 px MR horizontal overflow.

Likely source:

- `lib/ui2/screens/gate_scanned_screen.dart:118` uses `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` inside a `SingleChildScrollView`, which gives the row unbounded vertical constraints.
- `lib/ui2/screens/sale_form_screen.dart:250` uses the same stretch-row pattern inside a scrollable form.

Impact:

These are more serious than text clipping. They can prevent reliable layout, semantics, and screenshot/test rendering for the affected screens.

### P1: Widespread fixed-frame overflows

The stress test rendered every `kScreens` entry inside `PhoneFrame2` at the common narrow phone viewport.

Failing screens in English:

`home`, `cockpit`, `profile`, `signin`, `confirmForm`, `issueForm`, `issueOverlimit`, `issueWaiting`, `gateArrivals`, `gateScanned`, `gateGrn`, `dispatchList`, `saleForm`, `issueHistory`, `confHistory`, `unmatched`, `offlineGate`, `vHome`, `vAlert`, `vStock`

Failing screens in Marathi:

`home`, `cockpit`, `sync`, `profile`, `signin`, `confirmForm`, `issueForm`, `issueOverlimit`, `issueWaiting`, `gateArrivals`, `gateScanned`, `dispatchList`, `saleForm`, `issueHistory`, `confHistory`, `unmatched`, `offlineGate`, `vHome`, `vAlert`, `vStock`

Impact:

Operators and vendors can see clipped text, hidden status labels, or broken row contents in the phone-frame UI. This is especially risky because several affected screens are operational flows: gate entry, material issue, dispatch, sale, and vendor stock.

### P2: Home screen overflows on first launch

Source:

- `lib/ui2/screens/home_screen.dart:164`

Evidence:

- English: `RenderFlex overflowed by 36 pixels` and `106 pixels`.
- Marathi: `RenderFlex overflowed by 20 pixels` and `10 pixels`.
- The gallery shell also fails on the same Home screen overflow.

Likely cause:

The secondary action row uses `mainAxisAlignment: spaceBetween` with unconstrained title text and trailing widgets. In the phone frame, the available row width is too small for both children at natural size.

### P2: Vendor stock quantities overflow badly

Source:

- `lib/ui2/screens/v_stock_screen.dart:90`
- `lib/ui2/screens/v_stock_screen.dart:135`

Evidence:

- English: overflows up to 141 px.
- Marathi: overflows up to 141 px and 117 px.

Likely cause:

Large mono quantity text and unit/cover labels sit in a baseline `Row` without wrapping, scaling, or flexible constraints.

### P2: Repeated row-label pattern is fragile

Examples:

- `lib/ui2/screens/cockpit_screen.dart:180`
- `lib/ui2/screens/issue_form_screen.dart:381`
- `lib/ui2/screens/v_alert_screen.dart:189`

The same pattern appears across several screens: a compact card row contains multiple `Text` children, sometimes with badges or numeric values, without `Expanded`, `Flexible`, `FittedBox`, wrapping, or ellipsis behavior.

## Screens That Passed The Render Sweep

These screens did not appear in either EN or MR failure list:

`tasks`, `notifications`, `confirmSyncing`, `confirmSynced`, `confirmQueued`, `issueApproved`, `issueDone`, `gateScan`, `gateMatch`, `gateQc`, `gateReceived`, `dispatchDetail`, `gatePass`, `saleDone`, `offlineGateSaved`, `forceUpdate`, `vLogin`, `vOtp`

## Recommendations

1. Fix hard constraint bugs first.
   - Replace `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` inside scrollable/unbounded-height content.
   - Prefer `crossAxisAlignment: CrossAxisAlignment.start` or `center`, or give the row/card an explicit bounded height when stretch is required.

2. Create a shared compact-row primitive.
   - Most overflows are variations of label/value/trailing rows.
   - A shared widget should make the leading text `Expanded`, use `TextOverflow.ellipsis`, and constrain badges/status labels.

3. Treat 336 px frame width as a contract.
   - No row in `PhoneFrame2` should assume more than the inner content width after padding.
   - Add this to code review guidance for UI2 screens.

4. Keep the stress test.
   - `test/ui2_render_stress_test.dart` is intentionally failing right now because it reproduces the discovered layout bugs.
   - After fixes, this should become a normal CI regression test.

5. Add at least one visual/browser smoke path after layout fixes.
   - The production web build boots, but Flutter canvas makes DOM-level browser testing weak.
   - Widget render sweeps should be the primary guard; browser tests should verify boot, console cleanliness, and a few click flows.

## Reproduction

Run the focused stress sweep:

```bash
/Users/pawanpere/flutter-sdk/bin/flutter test test/ui2_render_stress_test.dart
```

Expected current result:

- The test fails.
- It lists the screens and overflow/constraint errors above.

Run the passing baseline checks:

```bash
/Users/pawanpere/flutter-sdk/bin/flutter analyze
/Users/pawanpere/flutter-sdk/bin/flutter test test/ui2_interactions_test.dart
/Users/pawanpere/flutter-sdk/bin/flutter build web --release --dart-define=UI2_MODE=true
```

