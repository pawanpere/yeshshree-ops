import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Vendor call-off alert — prototype screen [30]. A drill-down where the vendor
/// reviews Yeshshree's material need against a PO and their stock, then commits
/// a promise date (chosen via a picker) or proposes a change. Confirm shows a
/// "Confirmed" snackbar then pops; Propose change / Back simply pop.
class Ui2VAlertScreen extends StatefulWidget {
  const Ui2VAlertScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VAlertScreen> createState() => _Ui2VAlertScreenState();
}

class _Ui2VAlertScreenState extends State<Ui2VAlertScreen> {
  // Static call-off promise-date options (en / mr labels).
  static const _dates = <List<String>>[
    ['Thu 19 Jun', 'गुरु 19 जून'],
    ['Fri 20 Jun', 'शुक्र 20 जून'],
    ['Mon 23 Jun', 'सोम 23 जून'],
  ];

  PhoneNav get nav => widget.nav;

  int _dateIndex = 0;
  bool _busy = false;

  String get _dateLabel => S.t(_dates[_dateIndex][0], _dates[_dateIndex][1]);

  void _pickDate() {
    nav.overlay(Picker2Sheet<int>(
      title: S.t('Promise date', 'वचन तारीख'),
      options: [
        for (var i = 0; i < _dates.length; i++)
          Picker2Option<int>(S.t(_dates[i][0], _dates[i][1]), i),
      ],
      onPick: (i) {
        setState(() => _dateIndex = i);
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(I2.checkCircle, size: 18, color: Colors.white),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                  S.t('Confirmed · $_dateLabel', 'पुष्टी · $_dateLabel')),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // ---- Header: back + code pill + title ----
        ScreenHeader2(
          title: S.t('CALL-OFF', 'कॉल-ऑफ'),
          onBack: nav.pop,
          chip: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Y2.lineSoft,
              border: Border.all(color: const Color(0xFFD2DAE6)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('CO-7782', style: F.mono(12, color: Y2.accent)),
          ),
        ),
        // ---- Body ----
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Accent-tinted need card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x0F1D4ED8), // rgba(29,78,216,.06)
                    border: Border.all(color: const Color(0xFFBCD0F5)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: F.hind(13, color: Y2.ink, height: 1.45),
                      children: [
                        TextSpan(
                            text: S.t('Yeshshree needs:', 'येशश्रीला हवे:'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: S.t(
                                ' 2,000 kg CR coil 2.5 mm by ',
                                ' 2,000 kg CR कॉइल 2.5 mm — ')),
                        TextSpan(
                            text: S.t('Thu 19 Jun', 'गुरु 19 जून'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: S.t('.', 'पर्यंत.')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // PO / stock card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(S.t('Against PO', 'PO नुसार'),
                                style: F.hind(13, color: Y2.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false),
                          ),
                          const SizedBox(width: 8),
                          Text('77-2291',
                              style: F.mono(13, w: FontWeight.w700, color: Y2.ink)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(S.t('Your stock', 'तुमचा स्टॉक'),
                                style: F.hind(13, color: Y2.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('2,400 kg',
                                  style: F.mono(13,
                                      w: FontWeight.w700, color: Y2.green)),
                              const SizedBox(width: 5),
                              const Glyph(GlyphShape.dot, Y2.green, size: 8),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                // Prompt
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(S.t('Can you commit?', 'तुम्ही वचन देऊ शकता?'),
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                ),
                const SizedBox(height: 11),
                // Promise date card (reads as an editable select)
                Pressable2(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Y2.card,
                      border: Border.all(color: Y2.line),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(S.t('Promise date', 'वचन तारीख'),
                              style: F.hind(13, color: Y2.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(_dateLabel,
                                    style: F.hind(13,
                                        w: FontWeight.w700, color: Y2.ink),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false),
                              ),
                              const SizedBox(width: 4),
                              const Icon(I2.chevronDown,
                                  size: 20, color: Y2.muted),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ---- Footer actions ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: PrimaryButton2(
                  label: S.t('Confirm', 'पुष्टी करा'),
                  busy: _busy,
                  onTap: _confirm,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlineButton2(
                  label: S.t('Propose change', 'बदल सुचवा'),
                  onTap: nav.pop,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
