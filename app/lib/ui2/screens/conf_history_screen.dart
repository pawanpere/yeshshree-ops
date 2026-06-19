import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Confirmation history — prototype screen [33]. Today's posted/queued/synced
/// output confirmations for the line; a posted entry offers a tracked correction.
class Ui2ConfHistoryScreen extends StatelessWidget {
  const Ui2ConfHistoryScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('CONFIRMATION HISTORY', 'कन्फर्मेशन इतिहास'),
          subtitle: S.t('Line A · Shift B · today', 'लाइन A · पाळी B · आज'),
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Shift summary strip — top-line metrics for the log.
                _summaryStrip(),
                const SizedBox(height: 13),
                _entry(
                  title:
                      S.t('Front fork 4521 · 60 pc', 'फ्रंट फोर्क 4521 · 60 pc'),
                  status: _statusPill(
                      S.t('synced', 'सिंक झाले'), Y2.green, Y2.greenTint,
                      Y2.greenLine),
                  metaPrefix: '15:10 · PC-2261',
                  reject: S.t('2 reject', '2 नापास'),
                ),
                const SizedBox(height: 9),
                _entry(
                  title:
                      S.t('Front fork 4521 · 48 pc', 'फ्रंट फोर्क 4521 · 48 pc'),
                  status: _statusPill(S.t('queued', 'रांगेत'), Y2.orange,
                      Y2.orangeTint, Y2.orangeLine),
                  metaPrefix: S.t('14:02 · saved offline · will post',
                      '14:02 · ऑफलाइन जतन · पोस्ट होईल'),
                ),
                const SizedBox(height: 9),
                _entry(
                  title:
                      S.t('Front fork 4521 · 52 pc', 'फ्रंट फोर्क 4521 · 52 pc'),
                  status: _statusPill(S.t('posted', 'पोस्ट केले'), Y2.muted,
                      Y2.lineSoft, Y2.line),
                  metaPrefix: '12:40 · PC-2258',
                  flag: S.t('miscount?', 'चुकीची गणना?'),
                  borderColor: const Color(0xFFF0B89A),
                  action: Pressable2(
                    onTap: () => nav.sheet(SheetId.correction),
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Y2.accent),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                          S.t('Correct this entry', 'ही नोंद दुरुस्त करा'),
                          style:
                              F.hind(13, w: FontWeight.w600, color: Y2.accent)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t(
                      'A correction makes a tracked adjustment with a reason — the original post is never silently changed.',
                      'दुरुस्ती कारणासह नोंदलेला बदल करते — मूळ पोस्ट कधीही गुपचूप बदलली जात नाही.'),
                  textAlign: TextAlign.center,
                  style: F.hind(11, color: Y2.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact "160 pc · 2 rej · 98.8%" summary strip under the header.
  Widget _summaryStrip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.lineSoft,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Row(
          children: [
            _summaryCell(S.t('160 pc', '160 pc'),
                S.t('confirmed', 'पुष्टी केले'), Y2.ink),
            _summaryDivider(),
            _summaryCell('2', S.t('rejects', 'नापास'), Y2.red),
            _summaryDivider(),
            _summaryCell('98.8%', S.t('yield', 'उत्पादन'), Y2.green),
          ],
        ),
      );

  Widget _summaryCell(String value, String label, Color valueColor) => Expanded(
        child: Column(
          children: [
            Text(value, style: F.khand(17, ls: 0.2, color: valueColor)),
            const SizedBox(height: 2),
            Text(label, style: F.hind(10, color: Y2.muted)),
          ],
        ),
      );

  Widget _summaryDivider() =>
      Container(width: 1, height: 26, color: Y2.line);

  Widget _statusPill(String label, Color fg, Color bg, Color border) => Pill2(
        text: label,
        fg: fg,
        bg: bg,
        borderColor: border,
      );

  Widget _entry({
    required String title,
    required Widget status,
    required String metaPrefix,
    String? reject,
    String? flag,
    Color borderColor = Y2.line,
    Widget? action,
  }) =>
      Pressable2(
        onTap: () => nav.sheet(SheetId.correction),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(Y2.rRow),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(title,
                        style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  ),
                  const SizedBox(width: 8),
                  status,
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(metaPrefix,
                          style: F.hind(11, color: Y2.muted)),
                    ),
                    if (reject != null) ...[
                      const SizedBox(width: 6),
                      _rejectChip(reject),
                    ],
                    if (flag != null) ...[
                      const SizedBox(width: 6),
                      const Icon(I2.warning, size: 13, color: Y2.orange),
                      const SizedBox(width: 3),
                      Text(flag,
                          style: F.hind(11,
                              w: FontWeight.w600, color: Y2.orange)),
                    ],
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
        ),
      );

  /// Small red chip for a reject count so quality flags are scannable.
  Widget _rejectChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Y2.redTint,
          border: Border.all(color: Y2.redLine),
          borderRadius: BorderRadius.circular(Y2.rPill),
        ),
        child: Text(label,
            style: F.hind(10, w: FontWeight.w600, color: Y2.red)),
      );
}
