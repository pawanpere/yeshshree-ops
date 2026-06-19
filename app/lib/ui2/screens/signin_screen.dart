import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Sign-in / PIN entry — prototype screen [00]. Full-screen entry: no back
/// chevron, no tab bar. The keypad builds a 4-digit PIN; on the 4th digit it
/// calls the real `pinSwitch` auth, then navigates Home (still Home on error
/// for the demo, surfacing a "wrong PIN" message and clearing the buffer).
class Ui2SigninScreen extends ConsumerStatefulWidget {
  const Ui2SigninScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2SigninScreen> createState() => _Ui2SigninScreenState();
}

class _Ui2SigninScreenState extends ConsumerState<Ui2SigninScreen>
    with SingleTickerProviderStateMixin {
  // Label color #6b7689 — sits between Y2.body and Y2.muted in the prototype.
  static const _label = Color(0xFF6B7689);

  PhoneNav get nav => widget.nav;

  String _pin = '';
  bool _busy = false;
  bool _wrong = false;

  // Horizontal shake of the PIN-box row on a wrong PIN.
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _tapDigit(String d) {
    if (_busy || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _wrong = false;
    });
    if (_pin.length == 4) {
      HapticFeedback.heavyImpact();
      _verify();
    }
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _wrong = false;
    });
  }

  void _clear() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = '';
      _wrong = false;
    });
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).pinSwitch('sup1', _pin);
      if (mounted) nav.home();
    } catch (_) {
      // Demo: still navigate Home on a real auth failure so the flow is usable,
      // but surface the error state (red boxes, shake, error haptic) first so a
      // genuine wrong PIN isn't silent on a noisy floor.
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _wrong = true;
        _pin = '';
      });
      _shake.forward(from: 0);
      if (mounted) nav.home();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand mark
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Y2.accent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text('Y',
                      style: F.khand(28, color: Colors.white, height: 1)),
                ),
                Text(S.t('YESHSHREE OPS', 'येशश्री ऑप्स'),
                    style: F.khand(26, ls: 0.5, height: 1, color: Y2.ink)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('PLANT 1117 · LINE A TERMINAL',
                      style: F.mono(12, color: Y2.muted)),
                ),

                // Signed in as
                Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text(S.t('SIGNED IN AS', 'साइन इन'),
                      style:
                          F.hind(13, w: FontWeight.w600, ls: 0.4, color: _label)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Y2.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Y2.lineSoft,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFD2DAE6)),
                        ),
                        child: Text('RK', style: F.khand(16, color: Y2.ink)),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ramesh K.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: F.hind(16,
                                    w: FontWeight.w600,
                                    height: 1,
                                    color: Y2.ink)),
                            Text(S.t('Supervisor', 'सुपरवायझर'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: F.hind(12, color: Y2.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Enter PIN
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                            _busy
                                ? S.t('Signing in…', 'साइन इन होत आहे…')
                                : (_wrong
                                    ? S.t('Wrong PIN — try again',
                                        'चुकीचा पिन — पुन्हा')
                                    : S.t('ENTER PIN', 'पिन टाका')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: F.hind(13,
                                w: FontWeight.w600,
                                ls: 0.4,
                                color: _wrong ? Y2.red : _label)),
                      ),
                      const SizedBox(width: 8),
                      Text(S.t('4 digits', '4 अंक'),
                          style: F.hind(12, color: Y2.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // PIN boxes + an inline spinner that fades in while verifying.
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    final dx = math.sin(_shake.value * math.pi * 4) *
                        10 *
                        (1 - _shake.value);
                    return Transform.translate(
                        offset: Offset(dx, 0), child: child);
                  },
                  child: Row(
                    children: [
                      _pinBox(0),
                      const SizedBox(width: 11),
                      _pinBox(1),
                      const SizedBox(width: 11),
                      _pinBox(2),
                      const SizedBox(width: 11),
                      _pinBox(3),
                      if (_busy) ...[
                        const SizedBox(width: 12),
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Y2.accent),
                        ),
                      ],
                    ],
                  ),
                ),

                // Keypad — dimmed + non-interactive while verifying.
                const Spacer(),
                IgnorePointer(
                  ignoring: _busy,
                  child: AnimatedOpacity(
                    opacity: _busy ? 0.5 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Column(
                      children: [
                        _keyRow(['1', '2', '3']),
                        const SizedBox(height: 9),
                        _keyRow(['4', '5', '6']),
                        const SizedBox(height: 9),
                        _keyRow(['7', '8', '9']),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            _key(child: _altKey(S.t('Clear', 'पुसा')), onTap: _clear),
                            const SizedBox(width: 9),
                            _key(
                                child: Text('0', style: F.khand(24, color: Y2.ink)),
                                onTap: () => _tapDigit('0')),
                            const SizedBox(width: 9),
                            _key(
                                child: const Icon(Icons.backspace_outlined,
                                    size: 22, color: Y2.muted),
                                onTap: _backspace,
                                alt: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pinBox(int index) {
    final filled = index < _pin.length;
    // While verifying, all boxes glow accent; otherwise the next box is accent.
    final active = _busy || index == _pin.length;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: _wrong ? Y2.redLine : (active ? Y2.accent : Y2.line),
            width: 1.5,
          ),
        ),
        child: Text(filled ? '•' : '', style: F.mono(26, color: Y2.ink)),
      ),
    );
  }

  Widget _keyRow(List<String> digits) => Row(
        children: [
          for (var i = 0; i < digits.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            _key(
                child: Text(digits[i], style: F.khand(24, color: Y2.ink)),
                onTap: () => _tapDigit(digits[i])),
          ],
        ],
      );

  Widget _altKey(String label) =>
      Text(label, style: F.hind(13, w: FontWeight.w600, color: Y2.muted));

  Widget _key(
          {required Widget child, required VoidCallback onTap, bool alt = false}) =>
      Expanded(
        // Pressable2 gives a scale + selectionClick haptic on tapDown, so each
        // key press is felt and seen even on a noisy plant floor.
        child: Pressable2(
          haptic: false, // digit/clear/backspace fire their own haptics
          scale: 0.94,
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: alt ? const Color(0xFFF6F8FB) : Y2.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Y2.line),
            ),
            child: child,
          ),
        ),
      );
}
