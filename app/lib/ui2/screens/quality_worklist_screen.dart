import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Quality — Worklist (Phase 3). The inward-QC queue: gate entries that passed the
/// gate and are MATCHED to a PO (status=open & match_status=matched) wait here for
/// the quality operator. Tapping one carries its context into the QC step
/// (inward QC → goods receipt). Loaded from [Data.qualityWorklist]; clearly-marked
/// DEMO fallback when the backend is unreachable or the table is empty.
class Ui2QualityWorklistScreen extends StatefulWidget {
  const Ui2QualityWorklistScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2QualityWorklistScreen> createState() =>
      _Ui2QualityWorklistScreenState();
}

class _Ui2QualityWorklistScreenState extends State<Ui2QualityWorklistScreen> {
  Loaded<List<Json>>? _data;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.qualityWorklist();
    if (!mounted) return;
    setState(() => _data = res);
  }

  void _startQc(Json row) {
    final live = !(_data?.demo ?? true);
    // Carry the picked entry into the QC → GRN flow. Only a LIVE row's id is real;
    // for a demo row clear it so the GRN step self-creates rather than receipting
    // a non-existent entry.
    Ui2Flow.set('gate.entryId', live ? row['id'] : null);
    Ui2Flow.set('gate.vehicle', '${row['vehicle'] ?? ''}');
    Ui2Flow.set('gate.supplier', '${row['supplier'] ?? ''}');
    Ui2Flow.set('gate.material', '${row['material'] ?? ''}');
    // Drives the QC branch (component = counted, rm = weighed).
    Ui2Flow.set('gate.category', '${row['category'] ?? 'rm'}');
    // This row's own expected qty, so QC pre-fills the received field and the
    // weighbridge tolerance against THIS entry (not a stale value / RM sample).
    Ui2Flow.set('gate.challan', '${row['qty_expected'] ?? ''}');
    nav.go(ScreenId.gateQc);
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- shared header pieces ----

  Widget _header() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return ScreenHeader2(
      title: S.t('QUALITY — WORKLIST', 'गुणवत्ता — कार्यसूची'),
      onBack: nav.pop,
      demo: loaded?.demo ?? false,
      trailing: rows.isEmpty
          ? null
          : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
    );
  }

  Widget get _empty => EmptyState2(
        icon: Icons.fact_check_outlined,
        title: S.t('All caught up', 'सर्व पूर्ण'),
        subtitle: S.t('No matched arrivals are waiting for inward QC.',
            'आवक QC साठी जुळलेली कोणतीही आवक प्रतीक्षेत नाही.'),
      );

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        const StatusBar2(),
        _header(),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? _empty
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                                S.t('${rows.length} waiting for QC',
                                    '${rows.length} QC च्या प्रतीक्षेत'),
                                style: F.hind(12, color: Y2.muted)),
                          );
                        }
                        return _card(rows[i - 1]);
                      },
                    ),
        ),
      ],
    );
  }

  // ---- desktop layout (data table) ----

  Widget _desktop() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        _header(),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 6)
              : rows.isEmpty
                  ? _empty
                  : ResponsiveContent(
                      maxWidth: 1200,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10, left: 2),
                              child: Text(
                                  S.t('${rows.length} waiting for QC',
                                      '${rows.length} QC च्या प्रतीक्षेत'),
                                  style: F.hind(12, color: Y2.muted)),
                            ),
                            _table(rows),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A gap is inserted
  // between adjacent columns (see _gap) so right-aligned numbers / pills never
  // butt up against the next column's text. Total fixed widths + gaps stay well
  // under 900px; the Vehicle column is the lone Expanded that absorbs the slack.
  static const _wSupplier = 220.0;
  static const _wQty = 124.0;
  static const _wStatus = 116.0;
  static const _wAction = 176.0;
  static const _gap = SizedBox(width: 16);

  /// Scale-to-fit wrapper so numeric / status cells never overflow their fixed
  /// column, whatever the font metrics.
  Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  Widget _table(List<Json> rows) {
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
                Expanded(child: _th(S.t('Vehicle', 'वाहन'))),
                _gap,
                SizedBox(
                    width: _wSupplier,
                    child: _th(S.t('Supplier · material', 'पुरवठादार · माल'))),
                _gap,
                SizedBox(
                    width: _wQty,
                    child: _th(S.t('Expected', 'अपेक्षित'), right: true)),
                _gap,
                SizedBox(width: _wStatus, child: _th(S.t('Status', 'स्थिती'))),
                _gap,
                SizedBox(width: _wAction, child: _th(S.t('Action', 'कृती'))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRow(Json row, bool last) {
    final vehicle =
        '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
    final supplier = '${row['supplier'] ?? '—'}';
    final material = '${row['material'] ?? '—'}';
    final qty = row['qty_expected'];
    final isComponent = '${row['category'] ?? 'rm'}' == 'component';
    final unit = isComponent ? S.t('pcs', 'नग') : 'kg';
    return Pressable2(
      scale: 0.99,
      onTap: () => _startQc(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Y2.lineSoft)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Vehicle (lone Expanded — absorbs the slack).
            Expanded(
              child: Text(vehicle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.mono(13, w: FontWeight.w700, color: Y2.ink)),
            ),
            _gap,
            // Supplier + material.
            SizedBox(
              width: _wSupplier,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(supplier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
                  Text(material,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(11, color: Y2.muted)),
                ],
              ),
            ),
            _gap,
            // Expected qty (numeric, right-aligned).
            SizedBox(
              width: _wQty,
              child: _fit(Text(
                  qty == null ? '—' : '$qty $unit',
                  maxLines: 1,
                  style: F.mono(13, w: FontWeight.w700, color: Y2.body))),
            ),
            _gap,
            // Status pill.
            SizedBox(
              width: _wStatus,
              child: _fit(
                Pill2(
                    text: S.t('matched', 'जुळले'),
                    fg: Y2.green,
                    bg: Y2.greenTint,
                    borderColor: Y2.greenLine),
                align: Alignment.centerLeft,
              ),
            ),
            _gap,
            // Start inward QC affordance.
            SizedBox(
              width: _wAction,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.science_outlined,
                      size: 15, color: Y2.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(S.t('Start inward QC', 'आवक QC सुरू करा'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            F.hind(13, w: FontWeight.w600, color: Y2.accent)),
                  ),
                  const Icon(I2.chevronRight, size: 18, color: Y2.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Json row) {
    final vehicle = '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
    final supplier = '${row['supplier'] ?? '—'}';
    final material = '${row['material'] ?? '—'}';
    final qty = row['qty_expected'];
    final isComponent = '${row['category'] ?? 'rm'}' == 'component';
    final unit = isComponent ? S.t('pcs', 'नग') : 'kg';
    return Pressable2(
      onTap: () => _startQc(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(vehicle,
                      style: F.mono(14, color: Y2.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Pill2(
                    text: S.t('matched', 'जुळले'),
                    fg: Y2.green,
                    bg: Y2.greenTint,
                    borderColor: Y2.greenLine),
              ],
            ),
            const SizedBox(height: 4),
            Text(supplier,
                style: F.hind(13, w: FontWeight.w600, color: Y2.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(material,
                      style: F.hind(12, color: Y2.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (qty != null) ...[
                  const SizedBox(width: 8),
                  Text(S.t('exp. $qty $unit', 'अपे. $qty $unit'),
                      style: F.hind(12, w: FontWeight.w600, color: Y2.body)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.science_outlined, size: 15, color: Y2.accent),
                const SizedBox(width: 6),
                Text(S.t('Start inward QC', 'आवक QC सुरू करा'),
                    style: F.hind(13, w: FontWeight.w600, color: Y2.accent)),
                const Spacer(),
                const Icon(I2.chevronRight, size: 18, color: Y2.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
