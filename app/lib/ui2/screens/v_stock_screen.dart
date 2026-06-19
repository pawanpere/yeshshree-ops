import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Vendor — Stock at Yeshshree drill-down (prototype screen [31]). Read-only:
/// the back chevron pops; the stock item cards are intentionally non-interactive
/// (informational), matching the prototype and the audit's intended design.
class Ui2VStockScreen extends StatelessWidget {
  const Ui2VStockScreen({super.key, required this.nav});
  final PhoneNav nav;

  // rgba(194,65,12,0.06) card fill + #f0b89a hairline (the low-stock card).
  static const _lowFill = Color(0x0FC2410C);
  static const _lowLine = Color(0xFFF0B89A);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('STOCK AT YESHSHREE', 'येशश्रीकडील स्टॉक'),
          onBack: nav.pop,
          demo: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _okItem(),
                const SizedBox(height: 11),
                _lowItem(),
                const SizedBox(height: 11),
                Text(
                  S.t(
                      "Cover = stock ÷ Yeshshree's daily usage. Low items are flagged for you to top up.",
                      'कव्हर = स्टॉक ÷ येशश्रीचा रोजचा वापर. कमी असलेल्या वस्तू भरून काढण्यासाठी खुणावल्या जातात.'),
                  style: F.hind(12, color: Y2.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _okItem() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('CR coil 2.5 mm',
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Glyph(GlyphShape.dot, Y2.green, size: 9),
                    const SizedBox(width: 5),
                    Text(S.t('OK', 'ठीक'),
                        style:
                            F.hind(11, w: FontWeight.w600, color: Y2.green)),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('2,400', style: F.mono(30, height: 0.8, color: Y2.ink)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(S.t('kg · ~6 days cover', 'kg · ~6 दिवस कव्हर'),
                        style: F.hind(12, color: Y2.green),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                  ),
                ],
              ),
            ),
            const AnimatedBar2(fraction: 0.60, color: Y2.green),
          ],
        ),
      );

  Widget _lowItem() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _lowFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _lowLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Fasteners M8',
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Glyph(GlyphShape.triangle, Y2.orange, size: 9),
                    const SizedBox(width: 5),
                    Text(S.t('LOW', 'कमी'),
                        style:
                            F.hind(11, w: FontWeight.w600, color: Y2.orange)),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('3,100', style: F.mono(30, height: 0.8, color: Y2.ink)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(S.t('pc · ~1 day cover', 'pc · ~1 दिवस कव्हर'),
                        style: F.hind(12, color: Y2.orange),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                  ),
                ],
              ),
            ),
            const AnimatedBar2(fraction: 0.15, color: Y2.orange),
          ],
        ),
      );
}
