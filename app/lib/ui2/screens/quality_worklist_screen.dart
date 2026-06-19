import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
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
    nav.go(ScreenId.gateQc);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('QUALITY — WORKLIST', 'गुणवत्ता — कार्यसूची'),
          onBack: nav.pop,
          demo: loaded?.demo ?? false,
          trailing: rows.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.fact_check_outlined,
                      title: S.t('All caught up', 'सर्व पूर्ण'),
                      subtitle: S.t(
                          'No matched arrivals are waiting for inward QC.',
                          'आवक QC साठी जुळलेली कोणतीही आवक प्रतीक्षेत नाही.'),
                    )
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

  Widget _card(Json row) {
    final vehicle = '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
    final supplier = '${row['supplier'] ?? '—'}';
    final material = '${row['material'] ?? '—'}';
    final qty = row['qty_expected'];
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
                  Text(S.t('exp. $qty kg', 'अपे. $qty kg'),
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
