import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Vendor — Stock at Yeshshree drill-down (prototype screen [31]). This vendor
/// supplies COMPONENTS; each card shows a days-of-cover bar. The low item lets
/// the vendor commit a resupply ETA inline (demo only — no backend call).
class Ui2VStockScreen extends StatefulWidget {
  const Ui2VStockScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VStockScreen> createState() => _Ui2VStockScreenState();
}

class _Ui2VStockScreenState extends State<Ui2VStockScreen> {
  // rgba(194,65,12,0.06) card fill + #f0b89a hairline (the low-stock card).
  static const _lowFill = Color(0x0FC2410C);
  static const _lowLine = Color(0xFFF0B89A);

  bool _picking = false; // ETA chooser revealed on the low item
  String? _eta; // committed ETA label (null until chosen)

  void _togglePicker() {
    if (!mounted) return;
    setState(() => _picking = !_picking);
  }

  void _commit(String choice) {
    if (!mounted) return;
    setState(() {
      _eta = choice;
      _picking = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('Resupply ETA committed', 'पुनर्पुरवठा ETA नोंदवली')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- shared bits ----

  ScreenHeader2 _header() => ScreenHeader2(
        title: S.t('STOCK AT YESHSHREE', 'येशश्रीकडील स्टॉक'),
        onBack: widget.nav.pop,
        demo: true,
      );

  Widget _footnote() => Text(
        S.t(
            "Cover = stock ÷ Yeshshree's daily usage. Low items are flagged for you to top up.",
            'कव्हर = स्टॉक ÷ येशश्रीचा रोजचा वापर. कमी असलेल्या वस्तू भरून काढण्यासाठी खुणावल्या जातात.'),
        style: F.hind(12, color: Y2.muted, height: 1.5),
      );

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _header(),
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
                _footnote(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- desktop layout (no StatusBar2; cards side-by-side, capped width) ----

  Widget _desktop() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: ResponsiveContent(
              maxWidth: 1200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardGrid2(
                    minTileWidth: 340,
                    maxColumns: 2,
                    gap: 16,
                    children: [
                      // Items are self-sizing card rows -> sit one per column.
                      _okItem(),
                      _lowItem(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _footnote(),
                ],
              ),
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
                  child: Text(S.t('Fasteners M8 hex', 'फास्टनर्स M8 हेक्स'),
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
                  Text('24,000', style: F.mono(30, height: 0.8, color: Y2.ink)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(S.t('EA · ~9 days cover', 'EA · ~9 दिवस कव्हर'),
                        style: F.hind(12, color: Y2.green),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                  ),
                ],
              ),
            ),
            const AnimatedBar2(fraction: 0.75, color: Y2.green),
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
                  child: Text(
                      S.t('Mounting bracket 7782', 'माउंटिंग ब्रॅकेट 7782'),
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
                  Text('1,800', style: F.mono(30, height: 0.8, color: Y2.ink)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(S.t('EA · ~2 days cover', 'EA · ~2 दिवस कव्हर'),
                        style: F.hind(12, color: Y2.orange),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                  ),
                ],
              ),
            ),
            const AnimatedBar2(fraction: 0.18, color: Y2.orange),
            const SizedBox(height: 12),
            _resupplyAction(),
          ],
        ),
      );

  // Inline resupply-ETA affordance: action -> chooser -> confirmed line.
  Widget _resupplyAction() {
    if (_eta != null) {
      return Row(
        children: [
          const Glyph(GlyphShape.dot, Y2.green, size: 9),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              S.t('ETA committed: ', 'ETA नोंदवली: ') + _eta!,
              style: F.hind(13, w: FontWeight.w600, color: Y2.green),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlineButton2(
          label: S.t('Commit resupply ETA', 'पुनर्पुरवठा ETA नोंदवा'),
          onTap: _togglePicker,
        ),
        if (_picking) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _etaChip(S.t('Tomorrow', 'उद्या')),
              _etaChip(S.t('In 2 days', '2 दिवसांत')),
              _etaChip(S.t('In 3 days', '3 दिवसांत')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _etaChip(String label) => Pressable2(
        onTap: () => _commit(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: _lowLine),
            borderRadius: BorderRadius.circular(Y2.rPill),
          ),
          child: Text(label,
              style: F.hind(12, w: FontWeight.w600, color: Y2.orange)),
        ),
      );
}
