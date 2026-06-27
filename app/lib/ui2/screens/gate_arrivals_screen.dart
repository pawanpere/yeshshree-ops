import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../roles.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';
import '../widgets/sla.dart';

/// Gate — Arrivals — prototype screen [11]. The gate inbox: open gate entries the
/// gate scanner-watcher posted to the backend (plus unknown/no-pre-advice ones).
/// Tapping a known arrival reviews & matches it to a PO ([ScreenId.gateMatch]); an
/// unknown one opens the unmatched folder. The footer offers only a manual "Add a
/// gate entry" (walk-ins / no-scan) — the app no longer captures with the camera.
/// Rows are loaded from [Data.gateArrivals]; falls back to clearly-marked DEMO data
/// when the backend is unreachable or the table is empty.
///
/// Role-aware: in the GATE role this is a strict scan-only, READ-ONLY inbox (rows
/// don't navigate; the only action is the "Scan invoice" button). In the QUALITY
/// role it is the receiving worklist — tapping an arrival runs match / multi-item
/// receive → inward QC → GRN, and the scan footer is hidden.
class Ui2GateArrivalsScreen extends ConsumerStatefulWidget {
  const Ui2GateArrivalsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2GateArrivalsScreen> createState() =>
      _Ui2GateArrivalsScreenState();
}

class _Ui2GateArrivalsScreenState extends ConsumerState<Ui2GateArrivalsScreen> {
  Loaded<List<Json>>? _data;

  /// GATE role → read-only scan-only inbox; STORE → GRN (count) worklist;
  /// QUALITY → QA worklist. Both STORE and QUALITY are tappable. Set at the top
  /// of [build] from the active role.
  Role? _role;
  bool _readOnly = false;
  // Stable reference for the GRN countdown, captured once so the deadlines tick
  // down instead of re-anchoring to "now" on every rebuild.
  final DateTime _loadTime = DateTime.now();

  PhoneNav get nav => widget.nav;

  /// GRN deadline for an open, matched entry (arrival + 3 days); null for
  /// unmatched / already-received rows or rows with no arrival time.
  DateTime? _dueFor(Json row) {
    if (_isUnmatched(row) || _isDone(row)) return null;
    final h = row['arrived_hours_ago'];
    if (h is! num) return null;
    return grnDueFrom(_loadTime, h);
  }

  /// Overdue / due-soon alert banner — live (ticks), hidden when nothing is at
  /// risk. This is the "which GRNs are not made" signal at the top of the inbox.
  Widget _alertBanner(List<Json> rows) {
    return SlaTick(
      builder: (context) {
        final now = DateTime.now();
        var overdue = 0, soon = 0;
        for (final r in rows) {
          final due = _dueFor(r);
          if (due == null) continue;
          switch (slaStateFor(due.difference(now))) {
            case SlaState.overdue:
              overdue++;
            case SlaState.soon:
              soon++;
            case SlaState.ok:
              break;
          }
        }
        if (overdue == 0 && soon == 0) return const SizedBox.shrink();
        final bad = overdue > 0;
        final c = bad ? Y2.red : Y2.orange;
        final parts = <String>[
          if (overdue > 0)
            S.t('$overdue GRN overdue', '$overdue GRN मुदतबाह्य'),
          if (soon > 0) S.t('$soon due within 24h', '$soon २४ तासांत देय'),
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bad ? Y2.redTint : Y2.orangeTint,
              border: Border.all(color: bad ? Y2.redLine : Y2.orangeLine),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 17, color: c),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${S.t('GRN deadline', 'GRN मुदत')} — ${parts.join(' · ')}',
                    style: F.hind(12, w: FontWeight.w700, color: c),
                  ),
                ),
                Text(S.t('3-day limit', '३-दिवस मर्यादा'),
                    style: F.hind(10, w: FontWeight.w600, color: c)),
              ],
            ),
          ),
        );
      },
    );
  }

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
    // GATE → strict scan-only read-only inbox; any other role (QUALITY) → the
    // tappable receiving worklist. Read before the row/footer builders run.
    _role = ref.watch(activeRoleProvider);
    _readOnly = _role == Role.gate;
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- shared header + footer ----

  ScreenHeader2 _header() {
    final (String en, String mr) = switch (_role) {
      Role.gate => ('GATE — ARRIVALS', 'गेट — आवक'),
      Role.store => ('STORE — GRN', 'स्टोअर — GRN'),
      _ => ('QUALITY — QA', 'गुणवत्ता — QA'),
    };
    return ScreenHeader2(
      title: S.t(en, mr),
      onBack: nav.pop,
      demo: _data?.demo ?? false,
      trailing: Text(_readOnly ? '1/4' : '${_data?.data.length ?? 0}',
          style: F.mono(12, color: Y2.muted)),
    );
  }

  /// Scan front door — GATE role only. In the QUALITY (receiving) role there is
  /// no footer: work is started by tapping an arrival row.
  Widget _footer() {
    if (!_readOnly) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FB),
        border: Border(top: BorderSide(color: Y2.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scanning happens at the gate scanner (the ScanJet folder-watcher
          // posts entries to the backend); the operator just works the inbox the
          // scanner feeds. Receiving the load is the Quality role's job now.
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
          // Live-OCR front door: scan/upload an invoice, read the PO with Google
          // Vision, pin the material — the gate operator's one and only action.
          PrimaryButton2(
            label: S.t('Scan invoice — live OCR', 'इनव्हॉइस स्कॅन — लाइव्ह OCR'),
            onTap: () => nav.go(ScreenId.gateScanOcr),
          ),
        ],
      ),
    );
  }

  EmptyState2 _empty() => EmptyState2(
        icon: I2.truck,
        title: S.t('No vehicles waiting', 'प्रतीक्षेत वाहन नाही'),
        subtitle: S.t(
            'Scanned challans from the gate scanner appear here. Add one manually if needed.',
            'गेट स्कॅनरमधील स्कॅन केलेली चलने इथे दिसतात. आवश्यक असल्यास स्वतः जोडा.'),
      );

  String _summaryLine(List<Json> rows) {
    final waiting = rows.where((r) => !_isUnmatched(r) && !_isDone(r)).length;
    final done = rows.where(_isDone).length;
    return S.t('$waiting waiting · $done done today',
        '$waiting प्रतीक्षेत · आज $done पूर्ण');
  }

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
                  ? _empty()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _alertBanner(rows),
                          Text(_summaryLine(rows),
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
        _footer(),
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
          child: ResponsiveContent(
            maxWidth: 1200,
            child: loaded == null
                ? const SkeletonRows(count: 4)
                : rows.isEmpty
                    ? _empty()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _alertBanner(rows),
                            Text(_summaryLine(rows),
                                style: F.hind(12, color: Y2.muted)),
                            const SizedBox(height: 11),
                            _table(rows),
                          ],
                        ),
                      ),
          ),
        ),
        _footer(),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A gap is inserted
  // between adjacent columns (see _gap) so right-aligned numbers never butt up
  // against the next column's text.
  static const _wSupplier = 200.0;
  static const _wType = 120.0;
  static const _wChallan = 110.0;
  static const _wMeta = 176.0;
  static const _wDue = 124.0;
  static const _wChevron = 22.0;
  static const _gap = SizedBox(width: 16);

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
                SizedBox(width: _wSupplier, child: _th(S.t('Supplier · material', 'पुरवठादार · माल'))),
                _gap,
                SizedBox(width: _wType, child: _th(S.t('Type', 'प्रकार'))),
                _gap,
                SizedBox(
                    width: _wChallan,
                    child: _th(S.t('On challan', 'चलनावर'), right: true)),
                _gap,
                SizedBox(width: _wMeta, child: _th(S.t('Status', 'स्थिती'))),
                _gap,
                SizedBox(width: _wDue, child: _th(S.t('GRN due', 'GRN मुदत'))),
                const SizedBox(width: _wChevron),
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

  /// One arrival as a table row. Mirrors the phone card's branching (unmatched /
  /// multi-item invoice / single item) so the tap target, nav destination, and
  /// shown fields are identical — only the layout differs.
  Widget _tableRow(Json row, bool last) {
    final unmatched = _isUnmatched(row);
    final due = _dueFor(row);

    // Resolve the same per-branch values the phone card computes.
    final String plate;
    final TextStyle plateStyle;
    final String supplierLine;
    final Widget typeCell;
    final String challanText;
    final String meta;
    final Color metaColor;
    final VoidCallback onTap;

    if (unmatched) {
      plate = S.t('Unknown vehicle', 'अज्ञात वाहन');
      plateStyle = F.hind(14, w: FontWeight.w600, color: Y2.ink);
      supplierLine = '—';
      typeCell = _fit(
          const Glyph(GlyphShape.triangle, Y2.orange, size: 12),
          align: Alignment.centerLeft);
      challanText = '—';
      meta = S.t('no pre-advice · tap to identify',
          'पूर्वसूचना नाही · ओळखण्यासाठी टॅप करा');
      metaColor = Y2.orange;
      onTap = () => nav.go(ScreenId.unmatched);
    } else {
      final supplier = '${row['supplier'] ?? '—'}';
      final eta = '${row['eta'] ?? '—'}';
      final items = row['items'];
      if (items is List && items.length > 1) {
        plate = '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
        plateStyle = F.mono(14, color: Y2.ink);
        supplierLine =
            '${_gep(row)}$supplier · ${S.t('${items.length} items', '${items.length} वस्तू')}';
        typeCell = _fit(_multiPill(items.length), align: Alignment.centerLeft);
        challanText = '—';
        meta = S.t('invoice ${row['invoice'] ?? '—'}',
            'चलन ${row['invoice'] ?? '—'}');
        metaColor = Y2.accent;
        onTap = () {
          _stashInvoice(row);
          nav.go(ScreenId.gateReceiveItems);
        };
      } else {
        final status = '${row['status'] ?? ''}'.toLowerCase();
        final isNew = status == 'new';
        final isDone = status == 'done';
        final isComp = '${row['category'] ?? 'rm'}' == 'component';
        final material = '${row['material'] ?? '—'}';
        final unit = isComp ? S.t('pcs', 'नग') : 'kg';
        final challan = _fmtNum('${row['challan'] ?? ''}');
        plate = '${row['vehicle'] ?? S.t('Unknown vehicle', 'अज्ञात वाहन')}';
        plateStyle = F.mono(14, color: Y2.ink);
        supplierLine = '${_gep(row)}$supplier · $material';
        typeCell = _fit(_categoryPill(isComp), align: Alignment.centerLeft);
        challanText = challan.isEmpty ? '—' : '$challan $unit';
        if (isDone) {
          meta = S.t('received', 'मिळाले');
          metaColor = Y2.muted;
        } else {
          meta = S.t('exp. $eta', 'अपे. $eta');
          metaColor = isNew ? Y2.accent : Y2.muted;
        }
        // Unified: a single-item arrival opens the same Receive screen as a
        // one-row invoice (Stores GRN / Quality QA), not the old match wizard.
        onTap = () {
          _stashSingleAsInvoice(row);
          nav.go(ScreenId.gateReceiveItems);
        };
      }
    }

    return Pressable2(
      scale: 0.99,
      // GATE role is read-only: rows display but don't navigate (scan only).
      onTap: _readOnly ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border:
              last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Vehicle / plate.
            Expanded(
              child: Text(plate,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: plateStyle),
            ),
            _gap,
            // Supplier · material.
            SizedBox(
              width: _wSupplier,
              child: Text(supplierLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(12, color: Y2.muted)),
            ),
            _gap,
            // Type chip.
            SizedBox(width: _wType, child: typeCell),
            _gap,
            // On challan (numeric, right-aligned).
            SizedBox(
              width: _wChallan,
              child: _fit(Text(challanText,
                  maxLines: 1,
                  style: F.mono(13, w: FontWeight.w600, color: Y2.ink))),
            ),
            _gap,
            // Status / meta.
            SizedBox(
              width: _wMeta,
              child: Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(12, w: FontWeight.w600, color: metaColor)),
            ),
            _gap,
            // GRN deadline countdown (live).
            SizedBox(
              width: _wDue,
              child: due == null
                  ? Text('—',
                      style: F.mono(12, color: Y2.muted2))
                  : _fit(SlaCountdown(due, dense: true),
                      align: Alignment.centerLeft),
            ),
            SizedBox(
              width: _wChevron,
              child: _readOnly
                  ? null
                  : const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ),
          ],
        ),
      ),
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
    // Multi-item invoice: one challan carrying several materials (possibly across
    // POs). Tapping opens the Receive Invoice screen where all lines are entered
    // together, rather than the single-item match → QC → GRN walk.
    final items = row['items'];
    if (items is List && items.length > 1) {
      return _vehicle(
        plate: plate,
        plateStyle: F.mono(14, color: Y2.ink),
        sub: '${_gep(row)}$supplier · ${S.t('${items.length} items', '${items.length} वस्तू')}',
        meta: S.t('invoice ${row['invoice'] ?? '—'}',
            'चलन ${row['invoice'] ?? '—'}'),
        metaColor: Y2.accent,
        badge: _multiPill(items.length),
        slaDue: _dueFor(row),
        onTap: () {
          _stashInvoice(row);
          nav.go(ScreenId.gateReceiveItems);
        },
      );
    }
    final status = '${row['status'] ?? ''}'.toLowerCase();
    final isNew = status == 'new';
    final isDone = status == 'done';
    final isComp = '${row['category'] ?? 'rm'}' == 'component';
    final material = '${row['material'] ?? '—'}';
    final unit = isComp ? S.t('pcs', 'नग') : 'kg';
    final challan = _fmtNum('${row['challan'] ?? ''}');
    // Third line: for new/open rows, expected time + challan qty so the operator
    // sees how much is inbound; for an already-received row, just "received".
    final String meta;
    if (isDone) {
      meta = S.t('received', 'मिळाले');
    } else if (challan.isEmpty) {
      meta = S.t('exp. $eta', 'अपे. $eta');
    } else {
      meta = S.t('exp. $eta · $challan $unit on challan',
          'अपे. $eta · चलनावर $challan $unit');
    }
    return _vehicle(
      plate: plate,
      plateStyle: F.mono(14, color: Y2.ink),
      // Supplier + the actual material on the truck — this is what makes each
      // entry distinct (RM coil vs a named component) instead of all looking alike.
      sub: '${_gep(row)}$supplier · $material',
      meta: meta,
      metaColor: isNew ? Y2.accent : Y2.muted,
      // Category chip (raw material vs purchased component) so the kind of arrival
      // reads at a glance and the match/QC steps can branch correctly.
      badge: _categoryPill(isComp),
      slaDue: _dueFor(row),
      // Unified: a single-item arrival opens the same Receive screen as a one-row
      // invoice (Stores GRN / Quality QA), not the old match wizard.
      onTap: () {
        _stashSingleAsInvoice(row);
        nav.go(ScreenId.gateReceiveItems);
      },
    );
  }

  /// Stash a SINGLE-item arrival as a one-line invoice so it opens the same
  /// Receive screen as a multi-item challan (unified flow). Wraps the row's own
  /// material / po / qty / stock fields into a one-element `gate.items` list.
  void _stashSingleAsInvoice(Json row) {
    Ui2Flow.set('gate.items', <Json>[
      {
        'material': row['material'],
        'category': row['category'] ?? 'rm',
        'po': row['po'],
        'ordered': row['ordered'],
        'challan': row['challan'],
        'on_hand': row['on_hand'],
        'stock_max': row['stock_max'],
        'stock_min': row['stock_min'],
      }
    ]);
    Ui2Flow.set('gate.invoice', '${row['invoice'] ?? ''}');
    Ui2Flow.set('gate.supplier', '${row['supplier'] ?? '—'}');
    Ui2Flow.set('gate.vehicle', '${row['vehicle'] ?? ''}');
    Ui2Flow.set('gate.entryNo', '${row['gate_entry_no'] ?? ''}');
    Ui2Flow.set('gate.arrivedHoursAgo', row['arrived_hours_ago']);
    Ui2Flow.set('gate.entryId', null);
  }

  /// Stash a whole multi-item invoice into the cross-screen flow so the Receive
  /// Invoice screen can show every line. `items` carries each line's material /
  /// category / po / ordered / challan.
  void _stashInvoice(Json row) {
    Ui2Flow.set('gate.items', row['items']);
    Ui2Flow.set('gate.invoice', '${row['invoice'] ?? ''}');
    Ui2Flow.set('gate.supplier', '${row['supplier'] ?? '—'}');
    Ui2Flow.set('gate.vehicle', '${row['vehicle'] ?? ''}');
    Ui2Flow.set('gate.entryNo', '${row['gate_entry_no'] ?? ''}');
    Ui2Flow.set('gate.arrivedHoursAgo', row['arrived_hours_ago']);
    Ui2Flow.set('gate.entryId', null);
  }

  Widget _multiPill(int n) => Pill2(
        text: S.t('$n ITEMS', '$n वस्तू'),
        fg: Y2.accent,
        bg: Y2.accent.withValues(alpha: 0.10),
        borderColor: Y2.accent.withValues(alpha: 0.30),
        dot: false,
      );

  /// "GE-26014 · " prefix carrying a row's gate-entry number (blank if none), so
  /// the gate-entry number is visible right on the inbox line.
  String _gep(Json row) {
    final g = '${row['gate_entry_no'] ?? ''}';
    return g.isEmpty ? '' : '$g · ';
  }

  /// Group thousands in a bare number string ("5860" → "5,860"); passes through
  /// anything that isn't a plain integer.
  String _fmtNum(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null) return raw.trim();
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }

  Widget _categoryPill(bool isComp) => Pill2(
        text: isComp
            ? S.t('COMPONENT', 'घटक')
            : S.t('RAW MATERIAL', 'कच्चा माल'),
        fg: isComp ? Y2.accent : Y2.body,
        bg: isComp ? Y2.accent.withValues(alpha: 0.10) : Y2.lineSoft,
        borderColor: isComp ? Y2.accent.withValues(alpha: 0.30) : Y2.line,
        dot: false,
      );

  Widget _vehicle({
    required String plate,
    required TextStyle plateStyle,
    required String sub,
    String? meta,
    Color metaColor = Y2.muted,
    Widget? badge,
    DateTime? slaDue,
    required VoidCallback onTap,
  }) {
    return Pressable2(
      // GATE role is read-only: rows display but don't navigate (scan only).
      onTap: _readOnly ? null : onTap,
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
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        badge,
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(12, color: Y2.muted)),
                  if (meta != null || slaDue != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (meta != null)
                          Expanded(
                            child: Text(meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: F.hind(11, color: metaColor)),
                          )
                        else
                          const Spacer(),
                        if (slaDue != null) ...[
                          const SizedBox(width: 8),
                          SlaCountdown(slaDue, dense: true),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!_readOnly) ...[
              const SizedBox(width: 6),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ],
        ),
      ),
    );
  }
}
