import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// My issues today — prototype screen [24]. Today's material issues; a flagged
/// row offers a tracked correction that opens the correction sheet.
class Ui2IssueHistoryScreen extends StatelessWidget {
  const Ui2IssueHistoryScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('MY ISSUES TODAY', 'आजचे माझे इश्यू'),
          onBack: nav.pop,
          trailing: Text(S.t('3 issues', '3 इश्यू'),
              style: F.hind(12, color: Y2.muted)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _syncedRow(
                  S.t('CR coil 2.5mm · 750 kg', 'CR कॉइल 2.5mm · 750 kg'),
                  S.t('12:16 · Line A · Press 3', '12:16 · Line A · Press 3'),
                ),
                const SizedBox(height: 9),
                _syncedRow(
                  S.t('Fasteners M8 · 12 box', 'फास्टनर्स M8 · 12 box'),
                  S.t('11:02 · Line B', '11:02 · Line B'),
                ),
                const SizedBox(height: 9),
                _flaggedRow(),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    S.t(
                        'A correction creates a tracked adjustment with a reason and posts to SAP — never a silent edit.',
                        'दुरुस्ती कारणासह नोंदवलेली ट्रॅक केलेली ॲडजस्टमेंट तयार करते आणि SAP ला पोस्ट होते — कधीही गुपचूप बदल नाही.'),
                    textAlign: TextAlign.center,
                    style: F.hind(11, color: Y2.muted, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _syncedRow(String title, String meta) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(title,
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                ),
                const SizedBox(width: 8),
                Pill2(
                  text: S.t('synced', 'सिंक झाले'),
                  fg: Y2.green,
                  bg: Y2.greenTint,
                  borderColor: Y2.greenLine,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(meta, style: F.hind(12, color: Y2.muted)),
            ),
          ],
        ),
      );

  Widget _flaggedRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.orangeTint,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFF0B89A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                      S.t('Paint 20L · 4 can', 'पेंट 20L · 4 can'),
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(I2.warning, size: 14, color: Y2.orange),
                    const SizedBox(width: 4),
                    Text(S.t('wrong qty?', 'चुकीची संख्या?'),
                        style:
                            F.hind(11, w: FontWeight.w600, color: Y2.orange)),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(S.t('10:40 · Line A', '10:40 · Line A'),
                  style: F.hind(12, color: Y2.muted)),
            ),
            const SizedBox(height: 10),
            Pressable2(
              onTap: () => nav.sheet(SheetId.correction),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Y2.accent),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                    S.t('Reverse or correct this issue',
                        'हा इश्यू उलट करा किंवा दुरुस्त करा'),
                    style: F.hind(13, w: FontWeight.w600, color: Y2.accent)),
              ),
            ),
          ],
        ),
      );
}
