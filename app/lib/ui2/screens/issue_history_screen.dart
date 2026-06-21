import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// My issues today — prototype screen [24]. Today's material issues; a flagged
/// row offers a tracked correction that opens the correction sheet.
///
/// Phone: a vertical stack of issue cards (synced rows + a flagged row whose
/// correction CTA opens the correction sheet). Desktop: the same issues as a
/// wide data table (Material · Time/Line · Status), the flagged row's status
/// cell carrying the same "wrong qty?" flag and an inline correction action.
class Ui2IssueHistoryScreen extends StatelessWidget {
  const Ui2IssueHistoryScreen({super.key, required this.nav});
  final PhoneNav nav;

  // The footnote shared by both layouts.
  String get _footnote => S.t(
      'A correction creates a tracked adjustment with a reason and posts to SAP — never a silent edit.',
      'दुरुस्ती कारणासह नोंदवलेली ट्रॅक केलेली ॲडजस्टमेंट तयार करते आणि SAP ला पोस्ट होते — कधीही गुपचूप बदल नाही.');

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged) ----

  Widget _phone() {
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
                    _footnote,
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

  // ---- desktop layout ----

  // Same issues, rendered as a wide data table. The flagged row keeps its
  // "wrong qty?" flag and surfaces the correction action inline.
  Widget _desktop() {
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('MY ISSUES TODAY', 'आजचे माझे इश्यू'),
          onBack: nav.pop,
          trailing: Text(S.t('3 issues', '3 इश्यू'),
              style: F.hind(12, color: Y2.muted)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: ResponsiveContent(
              maxWidth: 1200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _issuesTable(),
                  const SizedBox(height: 14),
                  Text(
                    _footnote,
                    textAlign: TextAlign.center,
                    style: F.hind(12, color: Y2.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A gap is inserted
  // between adjacent columns (see _gap) so right-aligned content never butts up
  // against the next column's text.
  // Fixed total = 16 (left pad) + _wTime + _wStatus + 2·gap + 16 (right pad)
  //             = 16 + 200 + 300 + 32 + 16 = 564, well under the 900px ceiling;
  // the Material column (Expanded) absorbs the rest.
  static const _wTime = 200.0;
  static const _wStatus = 300.0;
  static const _gap = SizedBox(width: 16);

  Widget _issuesTable() {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                Expanded(child: _th(S.t('Material', 'माल'))),
                _gap,
                SizedBox(
                  width: _wTime,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _th(S.t('When · line', 'वेळ · लाइन')),
                  ),
                ),
                _gap,
                SizedBox(
                  width: _wStatus,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _th(S.t('Status', 'स्थिती'), right: true),
                  ),
                ),
              ],
            ),
          ),
          _syncedTableRow(
            S.t('CR coil 2.5mm · 750 kg', 'CR कॉइल 2.5mm · 750 kg'),
            S.t('12:16 · Line A · Press 3', '12:16 · Line A · Press 3'),
          ),
          _syncedTableRow(
            S.t('Fasteners M8 · 12 box', 'फास्टनर्स M8 · 12 box'),
            S.t('11:02 · Line B', '11:02 · Line B'),
          ),
          _flaggedTableRow(),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRowFrame({required Widget child, bool last = false, Color? bg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Y2.lineSoft)),
        ),
        child: child,
      );

  Widget _syncedTableRow(String title, String meta) => _tableRowFrame(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
            ),
            _gap,
            SizedBox(
              width: _wTime,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.muted)),
              ),
            ),
            _gap,
            SizedBox(
              width: _wStatus,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Pill2(
                  text: S.t('synced', 'सिंक झाले'),
                  fg: Y2.green,
                  bg: Y2.greenTint,
                  borderColor: Y2.greenLine,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _flaggedTableRow() => _tableRowFrame(
        last: true,
        bg: Y2.orangeTint,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(S.t('Paint 20L · 4 can', 'पेंट 20L · 4 can'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
            ),
            _gap,
            SizedBox(
              width: _wTime,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(S.t('10:40 · Line A', '10:40 · Line A'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(12, color: Y2.muted)),
              ),
            ),
            _gap,
            SizedBox(
              width: _wStatus,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(I2.warning, size: 14, color: Y2.orange),
                    const SizedBox(width: 4),
                    Text(S.t('wrong qty?', 'चुकीची संख्या?'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            F.hind(11, w: FontWeight.w600, color: Y2.orange)),
                    const SizedBox(width: 10),
                    Pressable2(
                      scale: 0.97,
                      onTap: () => nav.sheet(SheetId.correction),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Y2.accent),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                            S.t('Reverse or correct',
                                'उलट करा किंवा दुरुस्त करा'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: F.hind(12,
                                w: FontWeight.w600, color: Y2.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

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
