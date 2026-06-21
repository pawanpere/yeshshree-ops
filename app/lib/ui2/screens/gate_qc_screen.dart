import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';
import '../widgets/qty_field2.dart';

/// Inward QC — prototype screen [15]. Editable received/weighbridge weight +
/// pass/fail quality check; the chosen weight and QC result are stashed into the
/// flow for the GRN step, then receive into store (-> GRN).
class Ui2GateQcScreen extends StatefulWidget {
  const Ui2GateQcScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateQcScreen> createState() => _Ui2GateQcScreenState();
}

class _Ui2GateQcScreenState extends State<Ui2GateQcScreen> {
  bool _pass = true; // QC default = Pass (primary branch)
  bool _photoAdded = false;
  String? _photoName; // file name of the captured photo, shown once added
  num _rejected = 0; // how much is being rejected (kg can be fractional, pcs whole)
  late final TextEditingController _weight =
      TextEditingController(text: _defaultReceived());

  static const double _tolerancePct = 1.0; // ±1% within tolerance

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the CTA + tolerance pill + cross-field hint on every keystroke
    // in the received weight/count field.
    _weight.addListener(() => setState(() {}));
  }

  /// The challan qty for this entry (carried from the gate match step); the
  /// weighbridge tolerance compares the received weight against it. Defaults to a
  /// sample when opened cold (dev jump-nav).
  double get _challanKg {
    final c = Ui2Flow.get<String>('gate.challan') ?? '';
    final n = double.tryParse(
        c.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), ''));
    return (n == null || n == 0) ? 4000 : n;
  }

  /// Pre-fill the received field with this entry's challan qty (operator edits to
  /// the actual weighed/counted value); a sample weight when there's no entry.
  String _defaultReceived() {
    final c = Ui2Flow.get<String>('gate.challan');
    final n = int.tryParse((c ?? '').trim());
    return n == null ? '3,980' : _grp(n);
  }

  /// Group thousands for display ("5860" → "5,860").
  String _grp(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  /// Numeric received qty (decimal-as-string), commas stripped.
  String get _receivedQty => _weight.text.replaceAll(',', '').trim();

  double? get _weightKg => double.tryParse(_receivedQty);

  // Received must parse to a positive number.
  bool get _weightValid => V.positive(_weightKg);

  // Cross-field: you can't reject more than was received.
  bool get _rejectedOk =>
      _weightKg != null && _rejected.toDouble() <= _weightKg!;

  // Receive into store is allowed only with a valid positive received qty and a
  // rejected qty that doesn't exceed it.
  bool get _valid => _weightValid && _rejectedOk;

  void _continue() {
    if (!_valid) return;
    Ui2Flow.set('gate.receivedQty', _receivedQty);
    Ui2Flow.set('gate.qcResult', _pass ? 'pass' : 'fail');
    Ui2Flow.set('gate.rejectedQty', _fmtQty(_rejected.toDouble()));
    nav.replace(ScreenId.gateGrn);
  }

  /// Open the camera and attach a single QC photo. Cancel leaves it unset; a
  /// platform error (no camera / permission) surfaces a SnackBar.
  Future<void> _capturePhoto() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.camera, maxWidth: 1600);
      if (!mounted) return;
      if (x != null) {
        setState(() {
          _photoAdded = true;
          _photoName = x.name;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.t('Could not open camera', 'कॅमेरा उघडता आला नाही')),
        ),
      );
    }
  }

  /// Accepted = received − rejected, floored at 0; received parsed from the
  /// editable weight/count field (decimal-as-string, commas stripped).
  double get _acceptedQty {
    final received = _weightKg ?? 0;
    final acc = received - _rejected.toDouble();
    return acc > 0 ? acc : 0;
  }

  /// Trim a trailing `.0` so whole numbers read cleanly in the helper line.
  String _fmtQty(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(3);

  /// The entry being QC'd, carried in from the quality worklist (or the gate
  /// match step). Shown under the title so the QC isn't context-free. Null when
  /// the screen is opened cold (dev jump-nav) — no subtitle then.
  String? _entryContext() {
    final parts = <String>[];
    for (final key in const ['gate.vehicle', 'gate.supplier']) {
      final v = Ui2Flow.get<String>(key);
      if (v != null && v.isNotEmpty) parts.add(v);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Inward QC branches by the material's plant category: a purchased component is
  /// counted in pieces, raw material is weighed on the weighbridge (Phase 4).
  bool get _isComponent => Ui2Flow.get<String>('gate.category') == 'component';

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- Header: back + title (entry context) + step counter. Shared by both
  // form factors (only StatusBar2 chrome differs). ----
  Widget _header() => ScreenHeader2(
        title: S.t('INWARD QC', 'आवक QC'),
        subtitle: _entryContext(),
        onBack: nav.pop,
        trailing: Text('3/4', style: F.mono(12, color: Y2.muted)),
      );

  // ---- Footer CTA. Shared by both form factors. ----
  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: PrimaryButton2(
          label: S.t('Receive into store', 'स्टोअरमध्ये घ्या'),
          enabled: _valid,
          onTap: _continue,
        ),
      );

  /// The form fields + helpers, identical on phone and desktop. The desktop
  /// branch centers this at a comfortable reading width; the phone branch shows
  /// it edge-to-edge in the 336px frame.
  Widget _body() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Text(
                    _isComponent
                        ? S.t('RECEIVED COUNT · PIECES', 'मिळालेली संख्या · नग')
                        : S.t('RECEIVED WEIGHT · WEIGHBRIDGE',
                            'मिळालेले वजन · वजनकाटा'),
                    style: F.hind(12, w: FontWeight.w600, color: Y2.muted)),
                const SizedBox(height: 11),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _weight,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          // kg OR pcs, so allow a decimal point; commas are kept
                          // for the grouped default and stripped before parsing.
                          // Letters can't be typed or pasted in.
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]')),
                          ],
                          style: F.mono(28, color: Y2.ink),
                          cursorColor: Y2.accent,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_isComponent ? S.t('pcs', 'नग') : 'kg',
                          style: F.hind(16, color: Y2.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                    _isComponent
                        ? S.t('counted at receipt', 'पावतीवेळी मोजले')
                        : S.t('from weighbridge', 'वजनकाट्यावरून'),
                    style: F.hind(11, color: Y2.muted)),
                const SizedBox(height: 11),
                // The weighbridge tolerance pill compares against a kg challan figure;
                // it's meaningless for counted components, so show it only for RM.
                if (!_isComponent) ...[
                  _tolerance(),
                  const SizedBox(height: 13),
                ],
                Text(S.t('QUALITY CHECK', 'गुणवत्ता तपासणी'),
                    style: F.hind(12, w: FontWeight.w600, color: Y2.muted)),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _qcBtn(
                        S.t('Pass', 'पास'),
                        icon: I2.check,
                        selected: _pass,
                        selColor: Y2.green,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _pass = true);
                        },
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _qcBtn(
                        S.t('Fail', 'फेल'),
                        icon: I2.close,
                        selected: !_pass,
                        selColor: Y2.red,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _pass = false);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                // ---- Rejected qty: how much of the receipt is rejected ----
                Text(S.t('REJECTED QTY', 'नापास प्रमाण'),
                    style: F.hind(12, w: FontWeight.w600, color: Y2.muted)),
                const SizedBox(height: 9),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: QtyField2(
                            value: _rejected,
                            onChanged: (v) => setState(() => _rejected = v),
                            color: Y2.red,
                            fontSize: 22,
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_isComponent ? S.t('pcs', 'नग') : 'kg',
                          style: F.hind(15, color: Y2.muted)),
                    ],
                  ),
                ),
                // Cross-field guard: rejected can't exceed received. Only show
                // when both are present and rejected actually exceeds received —
                // an empty/invalid received qty is flagged by the tolerance pill,
                // not here.
                if (_weightKg != null && _rejected.toDouble() > _weightKg!)
                  FieldHint(_isComponent
                      ? S.t('Rejected count can’t exceed received count',
                          'नापास संख्या मिळालेल्या संख्येपेक्षा जास्त असू शकत नाही')
                      : S.t('Rejected weight can’t exceed received weight',
                          'नापास वजन मिळालेल्या वजनापेक्षा जास्त असू शकत नाही')),
                const SizedBox(height: 6),
                Text(
                    S.t('Accepted = received − rejected = ${_fmtQty(_acceptedQty)} ${_isComponent ? 'pcs' : 'kg'}',
                        'स्वीकृत = मिळालेले − नापास = ${_fmtQty(_acceptedQty)} ${_isComponent ? 'नग' : 'kg'}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: F.hind(11, color: Y2.muted)),
                const SizedBox(height: 11),
                Pressable2(
                  onTap: _capturePhoto,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _photoAdded ? Y2.greenTint : Y2.card,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: _photoAdded
                              ? Y2.greenLine
                              : const Color(0xFFC2C9D4),
                          width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _photoAdded
                                ? I2.check
                                : Icons.photo_camera_outlined,
                            size: 16,
                            color: _photoAdded ? Y2.green : Y2.muted),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                              _photoAdded
                                  ? S.t('Photo added · ${_photoName ?? ''}',
                                      'फोटो जोडला · ${_photoName ?? ''}')
                                  : S.t('add photo (optional)',
                                      'फोटो जोडा (ऐच्छिक)'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: F.hind(12,
                                  color: _photoAdded ? Y2.green : Y2.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
      ); // _body Column

  // ---- Phone layout: device chrome + header + scrolling body + footer.
  // Byte-for-byte the original layout. ----
  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: _body(),
          ),
        ),
        _footer(),
      ],
    );
  }

  // ---- Desktop layout: NO StatusBar2 chrome. Header, then the same form
  // centered at a comfortable reading width, then the footer. ----
  Widget _desktop() {
    return Column(
      children: [
        _header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: ResponsiveContent(
              maxWidth: 720,
              child: _body(),
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  /// Live tolerance pill: green "within tolerance" vs orange "over tolerance",
  /// driven by the entered weight against the 4,000 kg challan figure.
  Widget _tolerance() {
    final w = _weightKg;
    final challanLabel = _grp(_challanKg.round());
    if (w == null) {
      return Text(
          S.t('vs $challanLabel challan · enter a weight',
              'vs $challanLabel चलन · वजन भरा'),
          style: F.hind(12, color: Y2.muted));
    }
    final diff = w - _challanKg;
    final pct = _challanKg == 0 ? 0.0 : (diff.abs() / _challanKg) * 100;
    final within = pct <= _tolerancePct;
    final fg = within ? Y2.green : Y2.orange;
    final sign = diff == 0 ? '' : (diff > 0 ? '+' : '−');
    return Row(
      children: [
        Flexible(
          child: Text(
              S.t('vs $challanLabel challan · $sign${diff.abs().round()} kg (${pct.toStringAsFixed(1)}%)',
                  'vs $challanLabel चलन · $sign${diff.abs().round()} kg (${pct.toStringAsFixed(1)}%)'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: F.hind(12, color: Y2.body)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: within ? Y2.greenTint : Y2.orangeTint,
              border: Border.all(color: within ? Y2.greenLine : Y2.orangeLine),
              borderRadius: BorderRadius.circular(Y2.rPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(within ? I2.check : I2.warning, size: 12, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                      within
                          ? S.t('within tolerance', 'सहनशीलतेत')
                          : S.t('over tolerance', 'सहनशीलतेबाहेर'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.hind(10, w: FontWeight.w600, color: fg)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _qcBtn(String label,
          {required IconData icon,
          required bool selected,
          required Color selColor,
          required VoidCallback onTap}) =>
      Pressable2(
        haptic: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selColor : Y2.card,
            borderRadius: BorderRadius.circular(10),
            border: selected ? null : Border.all(color: Y2.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: selected ? Colors.white : Y2.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: F.hind(15,
                        w: FontWeight.w600,
                        color: selected ? Colors.white : Y2.muted)),
              ),
            ],
          ),
        ),
      );
}
