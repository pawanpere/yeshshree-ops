import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Record output — confirmation form. Prototype screen [02]. Operator logs
/// good/reject counts with working stepper controls, picks a reject reason
/// (required when reject > 0), then posts via the confirmSyncing screen which
/// performs the real POST /confirmations.
class Ui2ConfirmFormScreen extends StatefulWidget {
  const Ui2ConfirmFormScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ConfirmFormScreen> createState() => _Ui2ConfirmFormScreenState();
}

class _Ui2ConfirmFormScreenState extends State<Ui2ConfirmFormScreen> {
  static const _f6 = Color(0xFFF6F8FB);
  static const _d2 = Color(0xFFD2DAE6);
  static const _plan = 200;
  static const _done = 120;

  PhoneNav get nav => widget.nav;

  int _good = 0;
  int _reject = 0;
  int _downtime = 0;
  int? _reasonId;
  String? _reasonLabel;

  void _addGood(int n) => setState(() => _good = (_good + n).clamp(0, 9999));
  void _addReject(int n) {
    setState(() {
      _reject = (_reject + n).clamp(0, 9999);
      if (_reject == 0) {
        _reasonId = null;
        _reasonLabel = null;
      }
    });
  }

  void _addDowntime(int n) =>
      setState(() => _downtime = (_downtime + n).clamp(0, 999));

  /// Loss % = reject / (good + reject) * 100 — auto-calculated, not a literal.
  double get _lossPct {
    final total = _good + _reject;
    if (total == 0) return 0;
    return _reject / total * 100;
  }

  Future<void> _pickReason() async {
    // Show a transient loading overlay while the reason codes load, so the tap
    // isn't a dead zone, and an empty-state sheet if none are configured.
    nav.overlay(const _PickerLoading());
    final res = await Data.reasonCodes(kind: 'reject');
    if (!mounted) return;
    final options = [
      for (final r in res.data)
        Picker2Option<int?>(
          S.t('${r['label_en'] ?? r['code']}', '${r['label_mr'] ?? r['label_en'] ?? r['code']}'),
          (r['id'] as num?)?.toInt(),
          sub: r['code'] as String?,
        ),
    ];
    if (options.isEmpty) {
      nav.overlay(_PickerEmpty(onClose: nav.hideOverlay));
      return;
    }
    nav.overlay(Picker2Sheet<int?>(
      title: S.t('Reject reason', 'नापास कारण'),
      options: options,
      onPick: (id) {
        final picked = options.firstWhere((o) => o.value == id);
        setState(() {
          _reasonId = id;
          _reasonLabel = picked.label;
        });
        nav.hideOverlay();
      },
    ));
  }

  bool get _valid => _good > 0 && !(_reject > 0 && _reasonId == null);

  void _submit() {
    if (!_valid) return; // the button is visibly disabled when invalid
    // Stash the request for the syncing screen to POST, + values for the result.
    Ui2Flow.set('confirm.good', _good);
    Ui2Flow.set('confirm.reject', _reject);
    Ui2Flow.set('confirm.done', _done + _good);
    Ui2Flow.set('confirm.plan', _plan);
    Ui2Flow.set('confirm.body', <String, dynamic>{
      'client_ref': Data.newRef(),
      'line_id': 1,
      'shift': 'B',
      'material_id': 180,
      'good_qty': '$_good',
      'rejected_qty': '$_reject',
      'reject_reason_id': _reject > 0 ? _reasonId : null,
      'downtime_min': _downtime,
      'kind': 'shift_close',
    });
    nav.replace(ScreenId.confirmSyncing);
  }

  @override
  Widget build(BuildContext context) {
    final reasonMissing = _reject > 0 && _reasonId == null;
    return Column(
      children: [
        const StatusBar2(),
        // Header — shared back affordance + doc chip + shift/line/started meta.
        ScreenHeader2(
          title: S.t('FRONT FORK', 'फ्रंट फोर्क'),
          onBack: nav.pop,
          subtitle: 'Line A · Shift B · ${S.t('Started', 'सुरू')} 14:02',
          chip: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Y2.lineSoft,
              border: Border.all(color: _d2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('4521', style: F.mono(12, color: Y2.accent)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(S.t('PLAN PROGRESS', 'योजना प्रगती'),
                            style: F.hind(11,
                                w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
                        Text('$_done/$_plan',
                            style: F.mono(13, color: Y2.navy)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Animated bar with a lighter "projected after this post"
                    // segment that grows as the good count is entered.
                    _PlanBar(
                      done: _done,
                      projected: (_done + _good).clamp(0, _plan),
                      plan: _plan,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // GOOD count card.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(S.t('GOOD COUNT', 'चांगली संख्या'),
                              style: F.hind(11,
                                  w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                          Text('+GOOD', style: F.mono(11, color: Y2.green)),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _stepBtn('−', 50, () => _addGood(-1),
                              border: _d2, color: Y2.ink),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _bigCount('$_good', Y2.ink, 50),
                          ),
                          const SizedBox(width: 12),
                          _stepBtn('+', 50, () => _addGood(1),
                              border: Y2.accent,
                              color: Y2.accent,
                              bg: const Color(0x121D4ED8)),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          _quickAdd('+1', () => _addGood(1)),
                          const SizedBox(width: 8),
                          _quickAdd('+5', () => _addGood(5)),
                          const SizedBox(width: 8),
                          _quickAdd('+10', () => _addGood(10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // REJECT count card.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(
                        color: reasonMissing ? Y2.redLine : Y2.line),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(S.t('REJECT COUNT', 'नापास संख्या'),
                              style: F.hind(11,
                                  w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                          if (reasonMissing)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Glyph(GlyphShape.diamond, Y2.red, size: 9),
                                const SizedBox(width: 6),
                                Text(S.t('REASON REQ.', 'कारण आवश्यक'),
                                    style: F.hind(10,
                                        w: FontWeight.w600,
                                        ls: 0.5,
                                        color: Y2.red)),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _stepBtn('−', 46, () => _addReject(-1),
                              border: _d2, color: Y2.ink, font: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _bigCount('$_reject',
                                _reject > 0 ? Y2.red : Y2.ink, 42),
                          ),
                          const SizedBox(width: 12),
                          _stepBtn('+', 46, () => _addReject(1),
                              border: _d2, color: Y2.ink, font: 26),
                        ],
                      ),
                      if (_reject > 0) ...[
                        const SizedBox(height: 11),
                        Pressable2(
                          onTap: _pickReason,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 12),
                            decoration: BoxDecoration(
                              color: _f6,
                              border: Border.all(
                                  color: reasonMissing ? Y2.redLine : Y2.line),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    _reasonLabel ??
                                        S.t('Select reason', 'कारण निवडा'),
                                    style: F.hind(14,
                                        color: _reasonLabel == null
                                            ? Y2.muted
                                            : Y2.ink)),
                                const Icon(I2.chevronDown,
                                    size: 20, color: Y2.muted),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Downtime — now an editable stepper (it ships in the body).
                    Expanded(child: _downtimeTile()),
                    const SizedBox(width: 11),
                    // Loss — auto-calculated live from the entered reject count.
                    Expanded(child: _lossTile()),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Footer.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: _f6,
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text.rich(
                  TextSpan(
                    style: F.hind(11,
                        w: FontWeight.w400, ls: 0.4, color: Y2.muted),
                    children: [
                      TextSpan(text: S.t('AFTER THIS POST →', 'या नोंदीनंतर →')),
                      const TextSpan(text: ' '),
                      TextSpan(
                          text: '${_done + _good}/$_plan',
                          style: F.mono(13, color: Y2.ink)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: OutlineButton2(
                      label: S.t('Save interim', 'तात्पुरते जतन'),
                      onTap: nav.pop,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 13,
                    // Visibly disabled until a good count (and any required
                    // reason) is present — no more silent snackbar-on-invalid.
                    child: PrimaryButton2(
                      label: S.t('Close shift', 'पाळी संपवा'),
                      enabled: _valid,
                      onTap: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // A count that cross-fades when it changes, so +10 feels distinct from +1.
  Widget _bigCount(String value, Color color, double size) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Text(value,
            key: ValueKey(value),
            textAlign: TextAlign.center,
            style: F.mono(size, height: 0.8, color: color)),
      );

  Widget _stepBtn(String glyph, double dim, VoidCallback onTap,
          {required Color border,
          required Color color,
          Color? bg,
          double font = 28}) =>
      Pressable2(
        scale: 0.92,
        onTap: onTap,
        child: Container(
          width: dim,
          height: dim,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(glyph,
              style: F.khand(font, w: FontWeight.w400, color: color)),
        ),
      );

  Widget _quickAdd(String label, VoidCallback onTap) => Expanded(
        child: Pressable2(
          scale: 0.94,
          onTap: onTap,
          // 44px min height for gloved taps on the plant floor.
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _f6,
              border: Border.all(color: Y2.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
          ),
        ),
      );

  // Downtime tile — compact +/- stepper around an editable minute count.
  Widget _downtimeTile() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('Downtime', 'बंद वेळ'),
                style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 4),
            Row(
              children: [
                _miniStep('−', () => _addDowntime(-5)),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: F.mono(18, color: Y2.navy),
                      children: [
                        TextSpan(text: '$_downtime'),
                        TextSpan(
                            text: S.t(' min', ' मि'),
                            style: F.hind(12,
                                w: FontWeight.w400, color: Y2.muted)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                _miniStep('+', () => _addDowntime(5)),
              ],
            ),
          ],
        ),
      );

  Widget _miniStep(String glyph, VoidCallback onTap) => Pressable2(
        scale: 0.9,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: _d2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(glyph, style: F.khand(20, color: Y2.ink)),
        ),
      );

  // Loss tile — auto-calculated, red when non-zero, with a clarifying caption.
  Widget _lossTile() {
    final nonZero = _lossPct > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Y2.card,
        border: Border.all(color: Y2.line),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('Loss', 'तोटा'),
              style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
          Text.rich(
            TextSpan(
              style: F.mono(18, color: nonZero ? Y2.red : Y2.navy),
              children: [
                TextSpan(text: _lossPct.toStringAsFixed(1)),
                TextSpan(
                    text: ' %',
                    style: F.hind(12, w: FontWeight.w400, color: Y2.muted)),
              ],
            ),
          ),
          Text(S.t('auto-calculated', 'आपोआप मोजले'),
              style: F.hind(9, color: Y2.muted2)),
        ],
      ),
    );
  }
}

// Animated plan bar with a lighter "projected" overlay segment.
class _PlanBar extends StatelessWidget {
  const _PlanBar(
      {required this.done, required this.projected, required this.plan});
  final int done;
  final int projected;
  final int plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Y2.lineSoft,
        border: Border.all(color: Y2.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Stack(
        children: [
          // Projected (lighter) segment grows behind the committed fill.
          Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (projected / plan).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: const ColoredBox(color: Color(0x331D4ED8)),
              ),
            ),
          ),
          // Committed (solid) fill.
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (done / plan).clamp(0.0, 1.0),
              child: const ColoredBox(color: Y2.accent),
            ),
          ),
        ],
      ),
    );
  }
}

// Transient loading sheet shown while reason codes load.
class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

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
            margin: const EdgeInsets.only(bottom: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(S.t('Reject reason', 'नापास कारण'),
              style: F.khand(16, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 16),
          // SkeletonRows is a ListView; give it a bounded height inside this
          // min-sized Column.
          const SizedBox(height: 210, child: SkeletonRows(count: 3)),
        ],
      ),
    );
  }
}

// Empty sheet shown when no reject reasons are configured.
class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.onClose});
  final VoidCallback onClose;

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
            margin: const EdgeInsets.only(bottom: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          EmptyState2(
            icon: I2.inbox,
            title: S.t('No reject reasons', 'नापास कारणे नाहीत'),
            subtitle: S.t('None are configured yet.',
                'अद्याप कोणतीही सेट केलेली नाहीत.'),
            action: OutlineButton2(
              label: S.t('Close', 'बंद करा'),
              onTap: onClose,
            ),
          ),
        ],
      ),
    );
  }
}
