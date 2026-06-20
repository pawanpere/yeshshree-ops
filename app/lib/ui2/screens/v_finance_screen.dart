import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Vendor — Financial position (phone tab root). Two reads stitched together:
/// [Data.vendorExposure] (credit + qty exposure against limits) drives the top
/// exposure card, and [Data.vendorDebitNotes] drives the "Debit notes" list
/// below. Both are vendor-scoped on the server (JWT vendor_id). DEMO marker
/// shows when either read fell back to demo data.
class Ui2VFinanceScreen extends StatefulWidget {
  const Ui2VFinanceScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2VFinanceScreen> createState() => _Ui2VFinanceScreenState();
}

class _Ui2VFinanceScreenState extends State<Ui2VFinanceScreen> {
  Loaded<Json>? _exposure;
  Loaded<List<Json>>? _notes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exposure = await Data.vendorExposure();
    final notes = await Data.vendorDebitNotes();
    if (!mounted) return;
    setState(() {
      _exposure = exposure;
      _notes = notes;
    });
  }

  /// Parse a string-or-num field defensively into a double (numbers arrive as
  /// strings from the API).
  double _num(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

  /// Compact INR: paise → rupees, then rupees → lakhs (₹3.2L).
  String _lakhs(double rupees) {
    final l = rupees / 100000;
    final s = l >= 100 ? l.toStringAsFixed(0) : l.toStringAsFixed(1);
    return '₹${s}L';
  }

  @override
  Widget build(BuildContext context) {
    final exposure = _exposure;
    final notes = _notes;
    final loading = exposure == null || notes == null;
    final demo = (exposure?.demo ?? false) || (notes?.demo ?? false);

    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('MONEY', 'पैसे'),
          demo: demo,
        ),
        Expanded(
          child: loading
              ? const SkeletonRows(count: 3)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
                  children: [
                    _exposureCard(exposure.data),
                    const SizedBox(height: 18),
                    Text(
                      S.t('Debit notes', 'डेबिट नोट्स'),
                      style: F.khand(15, ls: 0.3, color: Y2.ink),
                    ),
                    const SizedBox(height: 9),
                    ..._notesSection(notes.data),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _exposureCard(Json e) {
    final exposure = _num(e['credit_exposure']);
    final creditLimit = _num(e['credit_limit']);
    final qtyMt = _num(e['qty_mt']);
    final qtyLimitMt = _num(e['qty_limit_mt']);
    final creditFrac = creditLimit > 0 ? exposure / creditLimit : 0.0;
    final qtyFrac = qtyLimitMt > 0 ? qtyMt / qtyLimitMt : 0.0;
    final hot = creditFrac >= 0.85;

    return Card2(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.t('CREDIT EXPOSURE', 'क्रेडिट एक्सपोजर'),
            style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  _lakhs(exposure),
                  style: F.khand(30, color: hot ? Y2.red : Y2.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBar2(
            fraction: creditFrac,
            color: hot ? Y2.red : Y2.accent,
          ),
          const SizedBox(height: 6),
          Text(
            S.t('of ${_lakhs(creditLimit)} limit',
                '${_lakhs(creditLimit)} मर्यादेपैकी'),
            style: F.hind(11, color: Y2.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Y2.line),
          const SizedBox(height: 12),
          Text(
            S.t('QUANTITY AT VENDOR', 'विक्रेत्याकडे प्रमाण'),
            style: F.hind(11, w: FontWeight.w600, ls: 0.5, color: Y2.muted),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_fmtNum(qtyMt)} ',
                style: F.khand(22, color: Y2.ink),
              ),
              Text(
                S.t('MT', 'टन'),
                style: F.hind(12, w: FontWeight.w600, color: Y2.body),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedBar2(fraction: qtyFrac, color: Y2.green),
          const SizedBox(height: 6),
          Text(
            S.t('of ${_fmtNum(qtyLimitMt)} MT limit',
                '${_fmtNum(qtyLimitMt)} टन मर्यादेपैकी'),
            style: F.hind(11, color: Y2.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Format a quantity number compactly (drop trailing .0).
  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  List<Widget> _notesSection(List<Json> rows) {
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: EmptyState2(
            icon: Icons.receipt_long_outlined,
            title: S.t('No debit notes', 'डेबिट नोट्स नाहीत'),
            subtitle: S.t(
                'No shortage or quality debits have been raised against you.',
                'तुमच्याविरुद्ध कोणताही कमतरता किंवा गुणवत्ता डेबिट नाही.'),
          ),
        ),
      ];
    }
    final widgets = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 9));
      widgets.add(_noteCard(rows[i]));
    }
    return widgets;
  }

  Widget _noteCard(Json n) {
    final docNo = '${n['doc_no'] ?? '—'}';
    final status = '${n['status'] ?? ''}'.toLowerCase();
    final amount = _num(n['amount']);

    // draft = orange (not yet binding), approved/raised = red (you owe it).
    final raised = status == 'approved' || status == 'raised';
    final pillFg = raised ? Y2.red : Y2.orange;
    final pillBg = raised ? Y2.redTint : Y2.orangeTint;
    final pillBorder = raised ? Y2.redLine : Y2.orangeLine;

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
                child: Text(
                  docNo,
                  style: F.mono(14, color: Y2.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Pill2(
                text: _statusLabel(status),
                fg: pillFg,
                bg: pillBg,
                borderColor: pillBorder,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _kindLabel('${n['kind'] ?? ''}'),
                  style: F.hind(12, color: Y2.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${_fmtAmount(amount)}',
                style: F.mono(15, w: FontWeight.w600, color: Y2.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Plain INR amount with thousands grouping (debit notes are small enough to
  /// show in full rupees, e.g. ₹63,000).
  String _fmtAmount(double rupees) {
    final whole = rupees.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return buf.toString();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return S.t('approved', 'मंजूर');
      case 'raised':
        return S.t('raised', 'उभारले');
      case 'draft':
        return S.t('draft', 'मसुदा');
      default:
        return status.isEmpty
            ? S.t('draft', 'मसुदा')
            : status;
    }
  }

  String _kindLabel(String kind) {
    switch (kind.toLowerCase()) {
      case 'shortage_5x':
        return S.t('Shortage (5× penalty)',
            'कमतरता (5× दंड)');
      case 'shortage':
        return S.t('Shortage', 'कमतरता');
      case 'quality':
      case 'quality_reject':
        return S.t('Quality reject', 'गुणवत्ता नापास');
      case 'rate_diff':
        return S.t('Rate difference', 'दर फरक');
      default:
        // Humanize an unknown code: snake_case → Title Case.
        if (kind.isEmpty) return S.t('Debit note', 'डेबिट नोट');
        final words = kind.split('_').where((w) => w.isNotEmpty).map((w) {
          return w[0].toUpperCase() + w.substring(1);
        }).join(' ');
        return words;
    }
  }
}
