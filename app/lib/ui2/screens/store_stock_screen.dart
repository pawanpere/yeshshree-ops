import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Store — Stock Browse (Phase 6). A read-only window onto current stock balances
/// per material × location (RM / COMP / AT_VENDOR / FG). Loaded from
/// [Data.stockBalances]; a horizontal filter-chip row narrows the list to one
/// location (local state, no refetch). Clearly-marked DEMO fallback when the
/// backend is unreachable or the balances view is still empty.
class Ui2StoreStockScreen extends StatefulWidget {
  const Ui2StoreStockScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2StoreStockScreen> createState() => _Ui2StoreStockScreenState();
}

class _Ui2StoreStockScreenState extends State<Ui2StoreStockScreen> {
  Loaded<List<Json>>? _data;

  // null = All; otherwise one of the canonical location codes.
  String? _location;

  static const _locations = <String>['RM', 'COMP', 'AT_VENDOR', 'FG'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.stockBalances();
    if (!mounted) return;
    setState(() => _data = res);
  }

  // Bilingual + colored label for a location code.
  static String _locLabel(String loc) {
    switch (loc) {
      case 'RM':
        return S.t('RM', 'कच्चा माल');
      case 'COMP':
        return S.t('COMP', 'घटक');
      case 'AT_VENDOR':
        return S.t('AT VENDOR', 'विक्रेत्याकडे');
      case 'FG':
        return S.t('FG', 'तयार माल');
      default:
        return loc;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _data;
    final all = loaded?.data ?? const <Json>[];
    final rows = _location == null
        ? all
        : [
            for (final r in all)
              if ('${r['location'] ?? ''}' == _location) r
          ];
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('STOCK', 'स्टॉक'),
          demo: loaded?.demo ?? false,
          trailing: all.isEmpty
              ? null
              : Text('${rows.length}', style: F.mono(12, color: Y2.muted)),
        ),
        if (loaded != null && all.isNotEmpty) _filterBar(),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 5)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: Icons.inventory_2_outlined,
                      title: S.t('No stock', 'स्टॉक नाही'),
                      subtitle: _location == null
                          ? S.t('No stock balances to show.',
                              'दाखवण्यासाठी स्टॉक शिल्लक नाही.')
                          : S.t('No stock at this location.',
                              'या ठिकाणी स्टॉक नाही.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) => _card(rows[i]),
                    ),
        ),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Y2.line))),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(S.t('All', 'सर्व'), _location == null,
              () => setState(() => _location = null)),
          for (final loc in _locations)
            _chip(_locLabel(loc), _location == loc,
                () => setState(() => _location = loc)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0x141D4ED8) : Y2.card,
            border: Border.all(color: selected ? Y2.accent : Y2.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: F.hind(13,
                  w: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Y2.accent : Y2.body)),
        ),
      );

  Widget _card(Json row) {
    final loc = '${row['location'] ?? ''}';
    final name = '${row['material'] ?? S.t('Material #', 'मटेरियल #')}'
            '${row['material'] == null ? '${row['material_id'] ?? ''}' : ''}'
        .trim();
    final qty = double.tryParse('${row['qty']}') ?? 0;
    final uom = '${row['uom'] ?? ''}'.trim();
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
                child: Text(name.isEmpty ? '—' : name,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _locPill(loc),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_fmtQty(qty), style: F.mono(17, color: Y2.ink)),
              if (uom.isNotEmpty) ...[
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(uom, style: F.mono(11, color: Y2.muted)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // RM=accent, COMP=green tint, AT_VENDOR=orange, FG=navy tint.
  Widget _locPill(String loc) {
    Color fg;
    Color bg;
    Color border;
    switch (loc) {
      case 'RM':
        fg = Y2.accent;
        bg = const Color(0x141D4ED8);
        border = const Color(0x591D4ED8);
        break;
      case 'COMP':
        fg = Y2.green;
        bg = Y2.greenTint;
        border = Y2.greenLine;
        break;
      case 'AT_VENDOR':
        fg = Y2.orange;
        bg = Y2.orangeTint;
        border = Y2.orangeLine;
        break;
      case 'FG':
        fg = Y2.navy;
        bg = const Color(0x1411243F);
        border = const Color(0x5911243F);
        break;
      default:
        fg = Y2.muted;
        bg = Y2.lineSoft;
        border = Y2.line;
    }
    return Pill2(
        text: _locLabel(loc.isEmpty ? '—' : loc),
        fg: fg,
        bg: bg,
        borderColor: border,
        dot: false);
  }

  // Compact whole-number qty with thousands separators (qty arrives as a string).
  static String _fmtQty(double v) {
    final n = v.round();
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (n < 0 ? '-' : '') + buf.toString();
  }
}
