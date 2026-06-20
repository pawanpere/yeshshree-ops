import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';
import '../widgets/qty_field2.dart';

/// Store — Issue material form — prototype screen [06]. Operator picks the
/// material + destination line, steps the quantity, then submits a real
/// POST /issues (through the retry queue). Over the allowed limit, the primary
/// action hands off to the over-limit / ask-supervisor flow instead.
class Ui2IssueFormScreen extends ConsumerStatefulWidget {
  const Ui2IssueFormScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2IssueFormScreen> createState() => _Ui2IssueFormScreenState();
}

class _Ui2IssueFormScreenState extends ConsumerState<Ui2IssueFormScreen> {
  static const _limit = 500; // allowed today, kg
  // Hard physical ceiling: the "In stock" figure shown below ('2,400' kg). You
  // can never issue more than exists, so qty is capped here even above _limit.
  static const _stockCap = 2400; // in stock, kg

  PhoneNav get nav => widget.nav;

  int _qty = 350;

  // Material selection (defaults mirror the prototype literals).
  int? _materialId;
  String _materialCode = 'CR-25';
  String _materialDesc = S.t('CR coil 2.5mm', 'CR कॉइल 2.5mm');

  // Destination line selection.
  int _lineId = 1;
  String _lineLabel = S.t('Line A · Press 3', 'लाइन A · प्रेस 3');

  bool _busy = false;

  void _step(int d) => setState(() => _qty = (_qty + d).clamp(0, _stockCap));

  // Per-field validity (mirrors offline_gate_screen.dart style).
  // Qty must be a real amount and never exceed what's physically in stock.
  bool get _qtyValid => _qty > 0 && _qty <= _stockCap;
  bool get _qtyOverStock => _qty > _stockCap;
  // A material must be explicitly chosen — the prefilled default has no real id.
  bool get _materialValid => _materialId != null;
  // Single CTA gate: qty>0 && qty<=stockCap && _materialId!=null.
  bool get _canIssue => _qtyValid && _materialValid;

  Future<void> _pickMaterial() async {
    // Show the sheet immediately with a spinner while the read resolves.
    nav.overlay(const _PickerLoading2());
    final res = await Data.materials();
    if (!mounted) return;
    final options = [
      for (final m in res.data)
        Picker2Option<int?>(
          '${m['description'] ?? m['sap_code']}',
          (m['id'] as num?)?.toInt(),
          sub: m['sap_code'] as String?,
        ),
    ];
    nav.overlay(Picker2Sheet<int?>(
      title: S.t('Material', 'माल'),
      options: options,
      onPick: (id) {
        final m = res.data.firstWhere(
          (r) => (r['id'] as num?)?.toInt() == id,
          orElse: () =>
              res.data.isNotEmpty ? res.data.first : <String, dynamic>{},
        );
        setState(() {
          _materialId = id;
          _materialCode = '${m['sap_code'] ?? _materialCode}';
          _materialDesc = '${m['description'] ?? _materialDesc}';
        });
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _pickLine() async {
    nav.overlay(const _PickerLoading2());
    final res = await Data.lines();
    if (!mounted) return;
    final options = [
      for (final l in res.data)
        Picker2Option<int?>(
          '${l['name'] ?? l['id']}',
          (l['id'] as num?)?.toInt(),
          sub: l['plant'] as String?,
        ),
    ];
    nav.overlay(Picker2Sheet<int?>(
      title: S.t('Issue to', 'कुठे जारी'),
      options: options,
      onPick: (id) {
        final l = res.data.firstWhere(
          (r) => (r['id'] as num?)?.toInt() == id,
          orElse: () =>
              res.data.isNotEmpty ? res.data.first : <String, dynamic>{},
        );
        setState(() {
          _lineId = id ?? _lineId;
          _lineLabel = '${l['name'] ?? _lineLabel}';
        });
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _issue() async {
    if (_busy) return;
    if (_qty <= 0) {
      _snack(S.t('Enter a quantity first', 'आधी प्रमाण भरा'));
      return;
    }
    if (_qtyOverStock) {
      // Hard-block: cannot issue more than what is in stock.
      _snack(S.t('Quantity exceeds stock ($_stockCap kg)',
          'प्रमाण स्टॉकपेक्षा जास्त आहे ($_stockCap kg)'));
      return;
    }
    if (!_materialValid) {
      // No real material chosen yet — must pick one before issuing.
      _snack(S.t('Choose a material first', 'आधी माल निवडा'));
      return;
    }
    if (_qty > _limit) {
      // Over today's allowed limit → ask-supervisor / over-limit flow.
      nav.go(ScreenId.issueOverlimit);
      return;
    }
    setState(() => _busy = true);
    final res = await Data.submit(
      ref,
      '/issues',
      {
        'destination': 'inhouse',
        if (_materialId != null) 'material_id': _materialId,
        'qty': '$_qty',
        'line_id': _lineId,
      },
      label: '${S.t('Issue', 'जारी')} $_qty kg $_materialDesc',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res.status) {
      case WriteStatus.ok:
        Ui2Flow.set('issue.material', _materialDesc);
        Ui2Flow.set('issue.qty', _qty);
        Ui2Flow.set('issue.dest', _lineLabel);
        Ui2Flow.set('issue.doc', res.data?['id'] ?? res.data?['issue_id']);
        nav.replace(ScreenId.issueDone);
      case WriteStatus.queued:
        Ui2Flow.set('issue.material', _materialDesc);
        Ui2Flow.set('issue.qty', _qty);
        Ui2Flow.set('issue.dest', _lineLabel);
        nav.replace(ScreenId.issueDone);
      case WriteStatus.error:
        _snack(res.error?.message ??
            S.t('Could not issue', 'जारी करता आले नाही'));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // ---- Header: shared back affordance + title + mode pill ----
        ScreenHeader2(
          title: S.t('ISSUE MATERIAL', 'माल जारी करा'),
          onBack: nav.pop,
          trailing: Pill2(
            text: S.t('ONLINE', 'ऑनलाइन'),
            fg: Y2.green,
            bg: Y2.greenTint,
            borderColor: Y2.greenLine,
          ),
        ),
        // ---- Scrollable body ----
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Material (tappable → picker)
                Pressable2(
                  onTap: _pickMaterial,
                  child: _field(
                    label: S.t('Material', 'माल'),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          _codeChip(_materialCode),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(_materialDesc,
                                style: F.hind(15,
                                    w: FontWeight.w600, color: Y2.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false),
                          ),
                          const SizedBox(width: 8),
                          const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Issue to (dropdown row → line picker)
                Pressable2(
                  onTap: _pickLine,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Y2.card,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Y2.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.t('Issue to', 'कुठे जारी'),
                                  style: F.hind(11,
                                      w: FontWeight.w400, color: Y2.muted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false),
                              Text(_lineLabel,
                                  style: F.hind(15,
                                      w: FontWeight.w600, color: Y2.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // In stock / Allowed today
                Row(
                  children: [
                    Expanded(
                      child: _statBox(
                          S.t('In stock', 'स्टॉकमध्ये'), '2,400', 'kg'),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: _statBox(
                          S.t('Allowed today', 'आज परवानगी'), '$_limit', 'kg'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Quantity stepper
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    borderRadius: BorderRadius.circular(Y2.rCard),
                    border: Border.all(color: Y2.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text(
                            S.t('QUANTITY TO ISSUE · KG',
                                'जारी करायचे प्रमाण · KG'),
                            style: F.hind(11,
                                w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                      ),
                      Row(
                        children: [
                          _stepBtn(Icons.remove,
                              accent: false, onTap: () => _step(-10)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: QtyField2(
                              value: _qty,
                              max: _stockCap,
                              onChanged: (v) =>
                                  setState(() => _qty = v.toInt()),
                              color: _qtyOverStock
                                  ? Y2.red
                                  : (_qty > _limit ? Y2.orange : Y2.ink),
                              fontSize: 46,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _stepBtn(Icons.add,
                              accent: true, onTap: () => _step(10)),
                        ],
                      ),
                      // Inline hint when qty exceeds what's in stock.
                      if (_qtyOverStock)
                        FieldHint(S.t('Only $_stockCap kg in stock',
                            'फक्त $_stockCap kg स्टॉकमध्ये')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ---- Footer: primary Issue action ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: _qty > _limit
                ? S.t('Ask supervisor', 'सुपरवायझरला विचारा')
                : S.t('Issue $_qty kg', '$_qty kg जारी करा'),
            busy: _busy,
            // Gate: qty>0 && qty<=stockCap && _materialId!=null. (Over the
            // allowed limit but within stock stays enabled → supervisor flow.)
            enabled: _canIssue,
            onTap: _issue,
          ),
        ),
      ],
    );
  }

  Widget _field({required String label, required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            child,
          ],
        ),
      );

  Widget _codeChip(String code) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Y2.lineSoft,
          border: Border.all(color: const Color(0xFFD2DAE6)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(code, style: F.mono(12, color: Y2.accent)),
      );

  Widget _statBox(String label, String value, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.mono(17, color: Y2.ink)),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Text(' $unit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _stepBtn(IconData icon,
          {required bool accent, required VoidCallback onTap}) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent ? const Color(0x121D4ED8) : null,
            border:
                Border.all(color: accent ? Y2.accent : const Color(0xFFD2DAE6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: accent ? Y2.accent : Y2.ink),
        ),
      );
}

/// Sheet shown while a picker's `Data.*` read is still resolving — keeps the tap
/// from feeling dead and matches the Picker2Sheet shell.
class _PickerLoading2 extends StatelessWidget {
  const _PickerLoading2();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Y2.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(S.t('Loading…', 'लोड होत आहे…'),
              textAlign: TextAlign.center,
              style: F.hind(12, color: Y2.muted)),
        ],
      ),
    );
  }
}
