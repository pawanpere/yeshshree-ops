import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Production — Parked holds (phone). A read-only view for the supervisor of the
/// confirmations they PARKED because the SAP production order wasn't ready yet.
/// Each hold waits for PPC/planning to assign the SAP order — the supervisor
/// takes NO action here (planning resolves them on the office side). Loaded from
/// [Data.holds]; clearly-marked DEMO fallback when the backend is unreachable or
/// the holds table is still empty.
class Ui2ProductionHoldsScreen extends StatefulWidget {
  const Ui2ProductionHoldsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ProductionHoldsScreen> createState() =>
      _Ui2ProductionHoldsScreenState();
}

class _Ui2ProductionHoldsScreenState extends State<Ui2ProductionHoldsScreen> {
  Loaded<List<Json>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.holds();
    if (!mounted) return;
    setState(() => _data = res);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('PARKED HOLDS', 'पार्क केलेले होल्ड'),
          demo: loaded?.demo ?? false,
          trailing: rows.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 3)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.pause_circle_outline,
                      title: S.t('No parked holds', 'कोणतेही पार्क केलेले होल्ड नाहीत'),
                      subtitle: S.t(
                          'Confirmations you park while waiting for a SAP order show up here.',
                          'SAP ऑर्डरच्या प्रतीक्षेत तुम्ही पार्क केलेल्या पुष्टी येथे दिसतात.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        if (i == 0) return _caption();
                        return _card(rows[i - 1]);
                      },
                    ),
        ),
      ],
    );
  }

  // Explains WHY these are parked — planning will assign the SAP order, then the
  // parked confirmation posts automatically. The supervisor only waits.
  Widget _caption() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        S.t('Waiting for PPC to assign the SAP order. They post automatically once it arrives.',
            'PPC ने SAP ऑर्डर नेमण्याची प्रतीक्षा. ती मिळताच आपोआप पोस्ट होतील.'),
        style: F.hind(12, color: Y2.muted, height: 1.45),
      ),
    );
  }

  Widget _card(Json row) {
    final payload = (row['payload'] is Map)
        ? Json.from(row['payload'] as Map)
        : const <String, dynamic>{};
    final material = '${payload['material'] ?? 'Material #${row['material_id']}'}';
    final shift = '${payload['shift'] ?? '—'}';
    final goodQty = double.tryParse('${payload['good_qty']}') ?? 0;

    return Container(
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
                child: Text(material,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Pill2(
                  text: S.t('parked', 'पार्क केले'),
                  fg: Y2.orange,
                  bg: Y2.orangeTint,
                  borderColor: Y2.orangeLine),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _fact(S.t('Shift', 'शिफ्ट'), shift),
              _fact(S.t('Good qty', 'चांगली संख्या'),
                  '${goodQty.toStringAsFixed(0)} ${S.t('pcs', 'नग')}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule, size: 15, color: Y2.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    S.t('Waiting for PPC order', 'PPC ऑर्डरच्या प्रतीक्षेत'),
                    style: F.hind(12, w: FontWeight.w600, color: Y2.orange),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: F.hind(10, w: FontWeight.w600, ls: 0.3, color: Y2.muted)),
        const SizedBox(height: 1),
        Text(value, style: F.mono(13, color: Y2.body)),
      ],
    );
  }
}
