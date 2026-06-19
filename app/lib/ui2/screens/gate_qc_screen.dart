import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

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
  late final TextEditingController _weight =
      TextEditingController(text: '3,980');

  static const double _challanKg = 4000;
  static const double _tolerancePct = 1.0; // ±1% within tolerance

  PhoneNav get nav => widget.nav;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  /// Numeric received qty (decimal-as-string), commas stripped.
  String get _receivedQty => _weight.text.replaceAll(',', '').trim();

  double? get _weightKg => double.tryParse(_receivedQty);

  void _continue() {
    Ui2Flow.set('gate.receivedQty', _receivedQty);
    Ui2Flow.set('gate.qcResult', _pass ? 'pass' : 'fail');
    nav.replace(ScreenId.gateGrn);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // ---- Header: back + title + step counter ----
        ScreenHeader2(
          title: S.t('INWARD QC', 'आवक QC'),
          onBack: nav.pop,
          trailing: Text('5/6', style: F.mono(12, color: Y2.muted)),
        ),
        // ---- Body ----
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('RECEIVED WEIGHT · WEIGHBRIDGE',
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
                          style: F.mono(28, color: Y2.ink),
                          cursorColor: Y2.accent,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('kg', style: F.hind(16, color: Y2.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(S.t('from weighbridge', 'वजनकाट्यावरून'),
                    style: F.hind(11, color: Y2.muted)),
                const SizedBox(height: 11),
                _tolerance(),
                const SizedBox(height: 13),
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
                const SizedBox(height: 11),
                Pressable2(
                  onTap: () => setState(() => _photoAdded = !_photoAdded),
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
                                  ? S.t('photo added · tap to remove',
                                      'फोटो जोडला · काढण्यासाठी टॅप करा')
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
            ),
          ),
        ),
        // ---- Footer CTA ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: S.t('Receive into store', 'स्टोअरमध्ये घ्या'),
            onTap: _continue,
          ),
        ),
      ],
    );
  }

  /// Live tolerance pill: green "within tolerance" vs orange "over tolerance",
  /// driven by the entered weight against the 4,000 kg challan figure.
  Widget _tolerance() {
    final w = _weightKg;
    if (w == null) {
      return Text(
          S.t('vs 4,000 challan · enter a weight',
              'vs 4,000 चलन · वजन भरा'),
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
              S.t('vs 4,000 challan · $sign${diff.abs().round()} kg (${pct.toStringAsFixed(1)}%)',
                  'vs 4,000 चलन · $sign${diff.abs().round()} kg (${pct.toStringAsFixed(1)}%)'),
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
