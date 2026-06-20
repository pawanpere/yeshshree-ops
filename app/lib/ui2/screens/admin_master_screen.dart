import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Admin — Master Data (office). A read-only browse across the four master
/// datasets (Materials / Lines / Vendors / Customers) behind a top segmented
/// control. Each dataset loads lazily on first visit and is cached in [_cache],
/// so switching tabs never refetches. Per-tab DEMO marker (the active dataset's
/// [Loaded.demo]) shows in the header. Reads only — no edit. Renders inside the
/// office shell, so no [StatusBar2] and no back affordance (tab-root screen).
class Ui2AdminMasterScreen extends StatefulWidget {
  const Ui2AdminMasterScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2AdminMasterScreen> createState() => _Ui2AdminMasterScreenState();
}

class _Ui2AdminMasterScreenState extends State<Ui2AdminMasterScreen> {
  // 0 = Materials, 1 = Lines, 2 = Vendors, 3 = Customers.
  int _tab = 0;

  // Per-tab cache so switching back to a visited tab is instant (no refetch).
  // A missing key means "not loaded yet" → show the skeleton + kick off a load.
  final Map<int, Loaded<List<Json>>> _cache = {};

  // Tabs currently in-flight, so a quick double-switch doesn't double-fetch.
  final Set<int> _loading = {};

  @override
  void initState() {
    super.initState();
    _ensure(_tab);
  }

  // Lazily load the dataset for [tab] once; cache the result.
  Future<void> _ensure(int tab) async {
    if (_cache.containsKey(tab) || _loading.contains(tab)) return;
    _loading.add(tab);
    final res = await _fetch(tab);
    if (!mounted) return;
    setState(() {
      _cache[tab] = res;
      _loading.remove(tab);
    });
  }

  Future<Loaded<List<Json>>> _fetch(int tab) {
    switch (tab) {
      case 1:
        return Data.lines();
      case 2:
        return Data.vendors();
      case 3:
        return Data.customers();
      case 0:
      default:
        return Data.materials();
    }
  }

  void _select(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _ensure(tab);
  }

  static String _tabLabel(int tab) {
    switch (tab) {
      case 1:
        return S.t('Lines', 'लाईन');
      case 2:
        return S.t('Vendors', 'विक्रेते');
      case 3:
        return S.t('Customers', 'ग्राहक');
      case 0:
      default:
        return S.t('Materials', 'मटेरियल');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _cache[_tab];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('MASTER DATA', 'मास्टर डेटा'),
          demo: loaded?.demo ?? false,
          trailing: loaded == null
              ? null
              : Text('${loaded.data.length}',
                  style: F.mono(12, color: Y2.muted)),
        ),
        _tabBar(),
        Expanded(child: _body(loaded)),
      ],
    );
  }

  Widget _tabBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Y2.line))),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < 4; i++)
            _chip(_tabLabel(i), _tab == i, () => _select(i)),
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

  Widget _body(Loaded<List<Json>>? loaded) {
    if (loaded == null) return const SkeletonRows(count: 5);
    final rows = loaded.data;
    if (rows.isEmpty) return _empty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, i) => _card(rows[i]),
    );
  }

  Widget _empty() {
    switch (_tab) {
      case 1:
        return EmptyState2(
          icon: Icons.conveyor_belt,
          title: S.t('No lines', 'लाईन नाहीत'),
          subtitle: S.t('No production lines are configured yet.',
              'अद्याप कोणत्याही उत्पादन लाईन कॉन्फिगर केलेल्या नाहीत.'),
        );
      case 2:
        return EmptyState2(
          icon: Icons.local_shipping_outlined,
          title: S.t('No vendors', 'विक्रेते नाहीत'),
          subtitle: S.t('No vendors have been added yet.',
              'अद्याप कोणतेही विक्रेते जोडलेले नाहीत.'),
        );
      case 3:
        return EmptyState2(
          icon: Icons.storefront_outlined,
          title: S.t('No customers', 'ग्राहक नाहीत'),
          subtitle: S.t('No customers have been added yet.',
              'अद्याप कोणतेही ग्राहक जोडलेले नाहीत.'),
        );
      case 0:
      default:
        return EmptyState2(
          icon: Icons.category_outlined,
          title: S.t('No materials', 'मटेरियल नाही'),
          subtitle: S.t('No materials have been added yet.',
              'अद्याप कोणतेही मटेरियल जोडलेले नाही.'),
        );
    }
  }

  Widget _card(Json row) {
    switch (_tab) {
      case 1:
        return _lineCard(row);
      case 2:
        return _vendorCard(row);
      case 3:
        return _customerCard(row);
      case 0:
      default:
        return _materialCard(row);
    }
  }

  // ----- per-dataset cards (all read-only) -----

  // Materials: sap_code (mono) + description + category pill (+ uom).
  Widget _materialCard(Json row) {
    final sap = '${row['sap_code'] ?? '—'}';
    final desc = '${row['description'] ?? '—'}';
    final category = '${row['category'] ?? ''}'.trim();
    final uom = '${row['uom'] ?? ''}'.trim();
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(sap,
                    style: F.mono(13, color: Y2.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(width: 8),
                Pill2(
                    text: category,
                    fg: Y2.accent,
                    bg: const Color(0x141D4ED8),
                    borderColor: const Color(0x331D4ED8),
                    dot: false),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(desc,
              style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (uom.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(S.t('UOM $uom', 'एकक $uom'),
                style: F.hind(12, color: Y2.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  // Lines: name + plant.
  Widget _lineCard(Json row) {
    final name = '${row['name'] ?? '—'}';
    final plant = '${row['plant'] ?? ''}'.trim();
    return _shell(
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (plant.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(S.t('Plant $plant', 'प्लांट $plant'),
                style: F.mono(12, color: Y2.muted)),
          ],
        ],
      ),
    );
  }

  // Vendors: name + sap_code (+ gstin if present).
  Widget _vendorCard(Json row) {
    final name = '${row['name'] ?? '—'}';
    final sap = '${row['sap_code'] ?? ''}'.trim();
    final gstin = '${row['gstin'] ?? ''}'.trim();
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (sap.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(sap,
                    style: F.mono(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
          if (gstin.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(S.t('GSTIN $gstin', 'GSTIN $gstin'),
                style: F.mono(12, color: Y2.body),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  // Customers: name + sap_code.
  Widget _customerCard(Json row) {
    final name = '${row['name'] ?? '—'}';
    final sap = '${row['sap_code'] ?? ''}'.trim();
    return _shell(
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (sap.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(sap,
                style: F.mono(12, color: Y2.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  // Shared card chrome (white row card with hairline border).
  Widget _shell({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: child,
      );
}
