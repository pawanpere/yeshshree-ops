import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Gate — Arrivals — prototype screen [11]. The gate inbox: open gate entries the
/// gate scanner-watcher posted to the backend (plus unknown/no-pre-advice ones).
/// Tapping a known arrival reviews & matches it to a PO ([ScreenId.gateMatch]); an
/// unknown one opens the unmatched folder. The footer offers only a manual "Add a
/// gate entry" (walk-ins / no-scan) — the app no longer captures with the camera.
/// Rows are loaded from [Data.gateArrivals]; falls back to clearly-marked DEMO data
/// when the backend is unreachable or the table is empty.
class Ui2GateArrivalsScreen extends StatefulWidget {
  const Ui2GateArrivalsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateArrivalsScreen> createState() => _Ui2GateArrivalsScreenState();
}

class _Ui2GateArrivalsScreenState extends State<Ui2GateArrivalsScreen> {
  Loaded<List<Json>>? _data;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.gateArrivals();
    if (!mounted) return;
    setState(() => _data = res);
  }

  bool _isUnmatched(Json row) =>
      '${row['status'] ?? ''}'.toLowerCase() == 'unmatched';

  bool _isDone(Json row) {
    final s = '${row['status'] ?? ''}'.toLowerCase();
    return s == 'done' || s == 'received';
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    final waiting = rows.where((r) => !_isUnmatched(r) && !_isDone(r)).length;
    final done = rows.where(_isDone).length;
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('GATE — ARRIVALS', 'गेट — आवक'),
          onBack: nav.pop,
          demo: loaded?.demo ?? false,
          trailing: Text('1/4', style: F.mono(12, color: Y2.muted)),
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: I2.truck,
                      title: S.t('No vehicles waiting', 'प्रतीक्षेत वाहन नाही'),
                      subtitle: S.t(
                          'Scanned challans from the gate scanner appear here. Add one manually if needed.',
                          'गेट स्कॅनरमधील स्कॅन केलेली चलने इथे दिसतात. आवश्यक असल्यास स्वतः जोडा.'),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              S.t('$waiting waiting · $done done today',
                                  '$waiting प्रतीक्षेत · आज $done पूर्ण'),
                              style: F.hind(12, color: Y2.muted)),
                          const SizedBox(height: 9),
                          for (final row in rows) ...[
                            _vehicleRow(row),
                            const SizedBox(height: 9),
                          ],
                        ],
                      ),
                    ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scanning happens at the gate scanner (the ScanJet folder-watcher
              // posts entries to the backend); the app no longer captures with the
              // camera — the operator works the inbox the scanner feeds, and adds a
              // manual entry only for walk-ins / no-scan arrivals.
              Row(
                children: [
                  const Icon(Icons.document_scanner_outlined,
                      size: 15, color: Y2.muted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      S.t('Scanned challans appear here automatically.',
                          'स्कॅन केलेली चलने इथे आपोआप दिसतात.'),
                      style: F.hind(11, color: Y2.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PrimaryButton2(
                label: S.t('Add a gate entry', 'गेट नोंद जोडा'),
                onTap: () => nav.go(ScreenId.offlineGate),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vehicleRow(Json row) {
    final unmatched = _isUnmatched(row);
    final plate = '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
    final supplier = '${row['supplier'] ?? '—'}';
    final eta = '${row['eta'] ?? '—'}';
    if (unmatched) {
      return _vehicle(
        plate: S.t('Unknown vehicle', 'अज्ञात वाहन'),
        plateStyle: F.hind(14, w: FontWeight.w600, color: Y2.ink),
        sub: S.t('no pre-advice · tap to identify',
            'पूर्वसूचना नाही · ओळखण्यासाठी टॅप करा'),
        badge: const Glyph(GlyphShape.triangle, Y2.orange, size: 12),
        onTap: () => nav.go(ScreenId.unmatched),
      );
    }
    final isNew = '${row['status'] ?? ''}'.toLowerCase() == 'new';
    return _vehicle(
      plate: plate,
      plateStyle: F.mono(14, color: Y2.ink),
      sub: S.t('$supplier · exp. $eta', '$supplier · अपे. $eta'),
      badge: isNew
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Glyph(GlyphShape.ring, Y2.accent, size: 9),
                const SizedBox(width: 5),
                Text(S.t('NEW', 'नवीन'),
                    style: F.hind(11, w: FontWeight.w600, color: Y2.accent)),
              ],
            )
          : null,
      // The arrival came in from the gate scanner; tapping reviews & matches it
      // to a PO (then on to quality). No in-app camera capture any more.
      onTap: () => nav.go(ScreenId.gateMatch),
    );
  }

  Widget _vehicle({
    required String plate,
    required TextStyle plateStyle,
    required String sub,
    Widget? badge,
    required VoidCallback onTap,
  }) {
    return Pressable2(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(child: Text(plate, style: plateStyle)),
                      if (badge != null) badge,
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(sub, style: F.hind(12, color: Y2.muted)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(I2.chevronRight, size: 18, color: Y2.muted),
          ],
        ),
      ),
    );
  }
}
