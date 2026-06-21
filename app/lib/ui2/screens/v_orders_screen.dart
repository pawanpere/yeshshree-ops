import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Vendor — Orders & call-offs (phone). The vendor's own open purchase orders
/// (with remaining open quantity) and the upcoming delivery call-offs the plant
/// has scheduled against them. Both are scoped to the signed-in vendor on the
/// server. Read from [Data.vendorOrders] + [Data.vendorCalloffs] in parallel,
/// with a clearly-marked DEMO fallback when the backend is unreachable or the
/// tables are empty.
class Ui2VOrdersScreen extends StatefulWidget {
  const Ui2VOrdersScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VOrdersScreen> createState() => _Ui2VOrdersScreenState();
}

class _Ui2VOrdersScreenState extends State<Ui2VOrdersScreen> {
  Loaded<List<Json>>? _orders;
  Loaded<List<Json>>? _calloffs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Future.wait([Data.vendorOrders(), Data.vendorCalloffs()]);
    if (!mounted) return;
    setState(() {
      _orders = res[0];
      _calloffs = res[1];
    });
  }

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
    final orders = _orders;
    final calloffs = _calloffs;
    final loading = orders == null || calloffs == null;
    final demo = (orders?.demo ?? false) || (calloffs?.demo ?? false);

    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('ORDERS', 'ऑर्डर'),
          demo: demo,
        ),
        Expanded(
          child: loading
              ? const SkeletonRows(count: 4)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
                  children: [
                    _sectionHeader(
                      S.t('Open purchase orders', 'खुले खरेदी ऑर्डर'),
                      orders.data.length,
                    ),
                    const SizedBox(height: 9),
                    if (orders.data.isEmpty)
                      _emptyNote(S.t('No open purchase orders.',
                          'कोणतेही खुले खरेदी ऑर्डर नाहीत.'))
                    else
                      for (final o in orders.data) ...[
                        _poCard(o),
                        const SizedBox(height: 9),
                      ],
                    const SizedBox(height: 8),
                    _sectionHeader(
                      S.t('Call-offs', 'कॉल-ऑफ'),
                      calloffs.data.length,
                    ),
                    const SizedBox(height: 9),
                    if (calloffs.data.isEmpty)
                      _emptyNote(S.t('No call-offs scheduled.',
                          'कोणतेही कॉल-ऑफ नियोजित नाहीत.'))
                    else
                      for (final c in calloffs.data) ...[
                        _calloffCard(c),
                        const SizedBox(height: 9),
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  // ---- desktop layout (no StatusBar2 chrome; same data + behaviour) ----

  Widget _desktop() {
    final orders = _orders;
    final calloffs = _calloffs;
    final loading = orders == null || calloffs == null;
    final demo = (orders?.demo ?? false) || (calloffs?.demo ?? false);

    return Column(
      children: [
        ScreenHeader2(
          title: S.t('ORDERS', 'ऑर्डर'),
          demo: demo,
        ),
        Expanded(
          child: loading
              ? const SkeletonRows(count: 4)
              : ResponsiveContent(
                  maxWidth: 1200,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      _sectionHeader(
                        S.t('Open purchase orders', 'खुले खरेदी ऑर्डर'),
                        orders.data.length,
                      ),
                      const SizedBox(height: 11),
                      if (orders.data.isEmpty)
                        _emptyNote(S.t('No open purchase orders.',
                            'कोणतेही खुले खरेदी ऑर्डर नाहीत.'))
                      else
                        _poTable(orders.data),
                      const SizedBox(height: 20),
                      _sectionHeader(
                        S.t('Call-offs', 'कॉल-ऑफ'),
                        calloffs.data.length,
                      ),
                      const SizedBox(height: 11),
                      if (calloffs.data.isEmpty)
                        _emptyNote(S.t('No call-offs scheduled.',
                            'कोणतेही कॉल-ऑफ नियोजित नाहीत.'))
                      else
                        _calloffTable(calloffs.data),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ---- desktop tables ----

  /// Fixed column widths shared by header + rows so the cells line up. A gap is
  /// inserted between every adjacent column pair (see _gap) so right-aligned
  /// numbers/dates never butt up against the next column's text.
  static const _wPo = 140.0;
  static const _wQty = 150.0;
  static const _wDue = 120.0;
  static const _wStatus = 110.0;
  static const _gap = SizedBox(width: 16);

  /// Scale-to-fit wrapper so numeric cells never overflow their fixed column,
  /// whatever the font metrics (widget tests render with a fixed-width font).
  Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  Widget _th(double? w, String label, {bool right = false}) {
    final t = Text(label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));
    return w == null ? t : SizedBox(width: w, child: t);
  }

  Widget _poTable(List<Json> rows) {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                _th(_wPo, S.t('PO', 'PO')),
                _gap,
                Expanded(child: _th(null, S.t('Material', 'माल'))),
                _gap,
                _th(_wQty, S.t('Open / Ordered', 'खुले / ऑर्डर'), right: true),
                _gap,
                _th(_wDue, S.t('Due', 'देय'), right: true),
                _gap,
                _th(_wStatus, S.t('Status', 'स्थिती')),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _poRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _poRow(Json o, bool last) {
    final poNo = '${o['sap_po_no'] ?? '—'}';
    final material = '${o['material'] ?? '—'}';
    final uom = '${o['uom'] ?? ''}';
    final openQty = '${o['open_qty'] ?? '0'}';
    final orderedQty = '${o['ordered_qty'] ?? '0'}';
    final dueDate = '${o['due_date'] ?? '—'}';
    final status = '${o['status'] ?? ''}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _wPo,
            child: Text(poNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.mono(13, w: FontWeight.w700, color: Y2.ink)),
          ),
          _gap,
          Expanded(
            child: Text(material,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
          ),
          _gap,
          SizedBox(
            width: _wQty,
            child: _fit(Text(
              '$openQty / $orderedQty${uom.isEmpty ? '' : ' $uom'}',
              maxLines: 1,
              style: F.mono(12, w: FontWeight.w600, color: Y2.body),
            )),
          ),
          _gap,
          SizedBox(
            width: _wDue,
            child: _fit(Text(dueDate,
                maxLines: 1, style: F.mono(12, color: Y2.muted))),
          ),
          _gap,
          SizedBox(
            width: _wStatus,
            child: _fit(_statusPill(status), align: Alignment.centerLeft),
          ),
        ],
      ),
    );
  }

  Widget _calloffTable(List<Json> rows) {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                Expanded(child: _th(null, S.t('Material', 'माल'))),
                _gap,
                _th(_wQty, S.t('Qty', 'प्रमाण'), right: true),
                _gap,
                _th(_wDue, S.t('Call-off date', 'कॉल-ऑफ तारीख'), right: true),
                _gap,
                _th(_wStatus, S.t('Status', 'स्थिती')),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _calloffRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _calloffRow(Json c, bool last) {
    final material = '${c['material'] ?? '—'}';
    final qty = '${c['qty'] ?? '0'}';
    final calloffDate = '${c['calloff_date'] ?? '—'}';
    final status = '${c['status'] ?? ''}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(material,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
          ),
          _gap,
          SizedBox(
            width: _wQty,
            child: _fit(Text(qty,
                maxLines: 1,
                style: F.mono(13, w: FontWeight.w700, color: Y2.ink))),
          ),
          _gap,
          SizedBox(
            width: _wDue,
            child: _fit(Text(calloffDate,
                maxLines: 1, style: F.mono(12, color: Y2.muted))),
          ),
          _gap,
          SizedBox(
            width: _wStatus,
            child: _fit(_statusPill(status), align: Alignment.centerLeft),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, int count) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: F.khand(14, ls: 0.3, color: Y2.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text('$count', style: F.mono(12, color: Y2.muted)),
      ],
    );
  }

  Widget _emptyNote(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Text(text, style: F.hind(12, color: Y2.muted)),
    );
  }

  // status pill colours: open = accent, anything else (planned/closed) = muted.
  Pill2 _statusPill(String status) {
    final st = status.toLowerCase();
    if (st == 'open') {
      return Pill2(
        text: S.t('open', 'खुले'),
        fg: Y2.accent,
        bg: const Color(0x141D4ED8),
        borderColor: const Color(0x591D4ED8),
      );
    }
    final label = st == 'planned'
        ? S.t('planned', 'नियोजित')
        : st.isEmpty
            ? S.t('—', '—')
            : status;
    return Pill2(
      text: label,
      fg: Y2.muted,
      bg: Y2.lineSoft,
      borderColor: Y2.line,
    );
  }

  Widget _poCard(Json o) {
    final poNo = '${o['sap_po_no'] ?? '—'}';
    final material = '${o['material'] ?? '—'}';
    final uom = '${o['uom'] ?? ''}';
    final openQty = '${o['open_qty'] ?? '0'}';
    final orderedQty = '${o['ordered_qty'] ?? '0'}';
    final dueDate = '${o['due_date'] ?? '—'}';
    final status = '${o['status'] ?? ''}';

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
                child: Text(poNo,
                    style: F.mono(14, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _statusPill(status),
            ],
          ),
          const SizedBox(height: 4),
          Text(material,
              style: F.hind(13, w: FontWeight.w600, color: Y2.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$openQty / $orderedQty${uom.isEmpty ? '' : ' $uom'}',
                  style: F.hind(12, color: Y2.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.event_outlined, size: 13, color: Y2.muted),
              const SizedBox(width: 4),
              Text(dueDate, style: F.mono(11, color: Y2.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calloffCard(Json c) {
    final material = '${c['material'] ?? '—'}';
    final qty = '${c['qty'] ?? '0'}';
    final calloffDate = '${c['calloff_date'] ?? '—'}';
    final status = '${c['status'] ?? ''}';

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
                    style: F.hind(13, w: FontWeight.w600, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _statusPill(status),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(qty,
                    style: F.mono(14, color: Y2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.event_outlined, size: 13, color: Y2.muted),
              const SizedBox(width: 4),
              Text(calloffDate, style: F.mono(11, color: Y2.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
