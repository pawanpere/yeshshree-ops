import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Supervisor Cockpit — prototype screen [25]. Now / Team tabs; the data-viz
/// (progress + stat tiles) is the proof-slice chart test.
class Ui2CockpitScreen extends StatefulWidget {
  const Ui2CockpitScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2CockpitScreen> createState() => _Ui2CockpitScreenState();
}

class _Ui2CockpitScreenState extends State<Ui2CockpitScreen> {
  int _tab = 0; // 0 = Now, 1 = Team

  // Short demo yield trend (last ~6 readings) for the sparkline under yield.
  static const _yieldTrend = <double>[92, 94, 93, 95, 96, 96];

  PhoneNav get nav => widget.nav;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(S.t('LINE A · COCKPIT', 'लाइन A · कॉकपिट'),
                        style: F.khand(19, ls: 0.3, color: Y2.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                  ),
                  Pill2(
                      text: S.t('RUNNING', 'सुरू'),
                      fg: Y2.green,
                      bg: Y2.greenTint,
                      borderColor: Y2.greenLine),
                ],
              ),
              const SizedBox(height: 9),
              Row(children: [
                _seg(S.t('Now', 'आता'), 0),
                const SizedBox(width: 18),
                _seg(S.t('Team', 'टीम'), 1),
              ]),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            children: _tab == 0 ? _now() : _team(),
          ),
        ),
        BottomTabs2(active: 1, onTap: nav.tab),
      ],
    );
  }

  Widget _seg(String label, int i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: _tab == i ? Y2.accent : Colors.transparent,
                    width: 2.5)),
          ),
          child: Text(label,
              style: F.hind(13,
                  w: FontWeight.w600, color: _tab == i ? Y2.ink : Y2.muted)),
        ),
      );

  List<Widget> _now() => [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(Y2.rCard),
            border: Border.all(color: Y2.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(S.t('SHIFT PLAN', 'शिफ्ट प्लॅन'),
                      style: F.hind(11,
                          w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
                  // Count-up ticker on the plan position so the cockpit reads live.
                  Ticker2(132,
                      style: F.mono(14, color: Y2.navy), suffix: '/200'),
                ],
              ),
              const SizedBox(height: 7),
              // Animated fill (0 → 66%) on mount.
              const AnimatedBar2(fraction: 0.66),
              const SizedBox(height: 8),
              Text(
                  S.t('On pace · 66% at 4:10 pm · projected 198/200',
                      'वेळेत · 4:10 ला 66% · अंदाज 198/200'),
                  style: F.hind(12, color: Y2.body)),
            ],
          ),
        ),
        const SizedBox(height: 11),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _yieldStat()),
              const SizedBox(width: 11),
              Expanded(
                  child: _bigStat('22', null,
                      const Glyph(GlyphShape.triangle, Y2.orange, size: 11),
                      S.t('downtime min', 'डाउनटाइम मि'))),
            ],
          ),
        ),
        const SizedBox(height: 11),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => nav.go(ScreenId.notifications),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Y2.redTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Y2.redLine),
            ),
            child: Row(
              children: [
                const Glyph(GlyphShape.diamond, Y2.red, size: 11),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('1 approval waiting', '1 मंजुरी प्रतीक्षेत'),
                          style:
                              F.hind(14, w: FontWeight.w600, color: Y2.navy)),
                      Text('Sunita · +250 kg CR coil',
                          style: F.hind(11, color: Y2.muted)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(S.t('Act', 'कृती'),
                        style:
                            F.hind(13, w: FontWeight.w600, color: Y2.red)),
                    const SizedBox(width: 3),
                    const Icon(I2.arrowForward, size: 16, color: Y2.red),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        Pressable2(
          onTap: () => nav.go(ScreenId.confirmForm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
                color: Y2.accent, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(
                  child: Text(S.t('Record output now', 'आता आउटपुट नोंदवा'),
                      style: F.hind(16, w: FontWeight.w600, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false),
                ),
                const SizedBox(width: 8),
                const Icon(I2.arrowForward, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ];

  // Yield tile — count-up number with a trend sparkline, a delta-vs-target chip
  // and a target caption so 96% has meaning (Phase C data-viz).
  Widget _yieldStat() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rCard),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Ticker2(96,
                      style: F.mono(34, height: 0.8, color: Y2.navy),
                      suffix: ''),
                  Padding(
                    padding: const EdgeInsets.only(left: 1, bottom: 2),
                    child: Text('%',
                        style: F.hind(14, w: FontWeight.w400, color: Y2.muted)),
                  ),
                  const SizedBox(width: 10),
                  const Sparkline2(_yieldTrend,
                      width: 46, height: 20, color: Y2.green),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(S.t('yield', 'यील्ड'),
                  style: F.hind(11, color: Y2.muted)),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Y2.greenTint,
                    border: Border.all(color: Y2.greenLine),
                    borderRadius: BorderRadius.circular(Y2.rPill),
                  ),
                  child: Text(S.t('+1 vs target', '+1 लक्ष्यापेक्षा'),
                      style: F.hind(10, w: FontWeight.w600, color: Y2.green)),
                ),
                const SizedBox(width: 7),
                Text(S.t('target 95%', 'लक्ष्य 95%'),
                    style: F.hind(10, color: Y2.muted)),
              ]),
            ),
          ],
        ),
      );

  Widget _bigStat(String value, String? unit, Widget? glyph, String label) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rCard),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (glyph != null) ...[glyph, const SizedBox(width: 6)],
                  Ticker2(int.tryParse(value) ?? 0,
                      style: F.mono(34, height: 0.8, color: Y2.navy)),
                  if (unit != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 1, bottom: 2),
                      child: Text(unit,
                          style:
                              F.hind(14, w: FontWeight.w400, color: Y2.muted)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label, style: F.hind(11, color: Y2.muted)),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Glyph(GlyphShape.triangle, Y2.orange, size: 9),
                const SizedBox(width: 4),
                Text(S.t('4 min vs avg', 'सरासरीपेक्षा 4 मि'),
                    style: F.hind(10, w: FontWeight.w600, color: Y2.orange)),
              ]),
            ),
          ],
        ),
      );

  List<Widget> _team() => [
        _member('SP', 'Sunita P.', S.t('Operator · Press 3', 'ऑपरेटर · प्रेस 3'),
            S.t('on station', 'स्थानावर'), Y2.green, true),
        const SizedBox(height: 9),
        _member('VM', 'Vijay M.', S.t('Operator · Press 1', 'ऑपरेटर · प्रेस 1'),
            S.t('on station', 'स्थानावर'), Y2.green, true),
        const SizedBox(height: 9),
        _member('AK', 'Asha K.', S.t('QC · roving', 'QC · फिरते'),
            S.t('break', 'ब्रेक'), Y2.muted, false),
      ];

  Widget _member(String initials, String name, String role, String status,
          Color statusColor, bool onStation) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap a member to view their station/task detail. Cosmetic no-op for now
        // (member profile screen is out of scope and screens stay decoupled).
        onTap: () {},
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Y2.lineSoft,
                shape: BoxShape.circle,
                // On-station members get an accent status ring around initials.
                border: Border.all(
                    color: onStation ? Y2.green : const Color(0xFFD2DAE6),
                    width: onStation ? 1.5 : 1),
              ),
              child: Text(initials, style: F.khand(14, color: Y2.ink)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  Text(role, style: F.hind(11, color: Y2.muted)),
                ],
              ),
            ),
            // Real colored dot Glyph instead of the inline '●'/'—' text glyphs.
            Glyph(GlyphShape.dot, statusColor, size: 8),
            const SizedBox(width: 6),
            Text(status,
                style: F.hind(11, w: FontWeight.w600, color: statusColor)),
          ],
        ),
        ),
      );
}
