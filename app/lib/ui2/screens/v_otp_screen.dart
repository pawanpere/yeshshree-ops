import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Vendor OTP entry — prototype screen [38]. A numeric keypad builds the 4-digit
/// code into the OTP boxes; when full it verifies against the server (still
/// advances to the vendor home on error for the demo). The "change" link pops
/// back to login and the resend countdown ticks to a tappable "Resend code".
class Ui2VOtpScreen extends ConsumerStatefulWidget {
  const Ui2VOtpScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2VOtpScreen> createState() => _Ui2VOtpScreenState();
}

class _Ui2VOtpScreenState extends ConsumerState<Ui2VOtpScreen>
    with SingleTickerProviderStateMixin {
  String _code = '';
  bool _busy = false;
  bool _error = false;
  int _resendIn = 24;
  Timer? _timer;

  late final AnimationController _shake;

  PhoneNav get nav => widget.nav;

  String get _phone => Ui2Flow.get<String>('vendor.phone') ?? '+91 98XXX XXX21';

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 24);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _tapDigit(String d) {
    if (_busy || _code.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = false;
      _code += d;
    });
    if (_code.length == 4) _verify();
  }

  void _backspace() {
    if (_busy || _code.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = false;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).verifyOtp(_phone, _code);
      if (mounted) nav.replace(ScreenId.vHome);
    } catch (_) {
      // Demo: surface the wrong-code error state, then still enter the vendor
      // home on a real verification failure (after the operator sees the error).
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _busy = false;
        _error = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (mounted) nav.replace(ScreenId.vHome);
    }
  }

  Future<void> _resend() async {
    if (_resendIn > 0) return;
    try {
      await ref.read(authProvider.notifier).requestOtp(_phone);
    } catch (_) {
      // Ignore — demo only.
    }
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _code.length == 4;
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: BackButton2(onTap: nav.pop),
                ),
                const SizedBox(height: 8),
                Text(S.t('ENTER THE CODE', 'कोड टाका'),
                    style: F.khand(24, ls: 0.5, height: 1, color: Y2.ink)),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text.rich(
                    TextSpan(
                      style: F.hind(13, color: Y2.body),
                      children: [
                        TextSpan(
                            text: S.t('Sent to $_phone · ',
                                '$_phone ला पाठवले · ')),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: nav.pop,
                            child: Text(S.t('change', 'बदला'),
                                style: F.hind(13, color: Y2.accent)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    final dx = (_shake.isAnimating)
                        ? 8 *
                            (1 - _shake.value) *
                            ((_shake.value * 8).floor().isEven ? 1 : -1)
                        : 0.0;
                    return Transform.translate(
                        offset: Offset(dx, 0), child: child);
                  },
                  child: Row(
                    children: [
                      Expanded(child: _otpBox(0)),
                      const SizedBox(width: 10),
                      Expanded(child: _otpBox(1)),
                      const SizedBox(width: 10),
                      Expanded(child: _otpBox(2)),
                      const SizedBox(width: 10),
                      Expanded(child: _otpBox(3)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _error
                      ? Text(
                          S.t('Wrong code, try again',
                              'चुकीचा कोड, पुन्हा प्रयत्न करा'),
                          style: F.hind(12, w: FontWeight.w600, color: Y2.red))
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _resend,
                          child: Text.rich(
                            TextSpan(
                              style: F.hind(12, color: Y2.muted),
                              children: [
                                TextSpan(
                                    text: S.t(
                                        "Didn't get it? ", 'मिळाला नाही? ')),
                                TextSpan(
                                  text: _resendIn > 0
                                      ? S.t(
                                          'Resend in 0:${_resendIn.toString().padLeft(2, '0')}',
                                          '0:${_resendIn.toString().padLeft(2, '0')} मध्ये पुन्हा')
                                      : S.t('Resend code', 'कोड पुन्हा पाठवा'),
                                  style: F.hind(12,
                                      w: _resendIn > 0
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                      color: _resendIn > 0 ? Y2.ink : Y2.accent,
                                      decoration: _resendIn > 0
                                          ? null
                                          : TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 22),
                // Numeric keypad driving the OTP boxes (dimmed while verifying).
                Opacity(
                  opacity: _busy ? 0.5 : 1,
                  child: IgnorePointer(
                    ignoring: _busy,
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
                            const Expanded(child: SizedBox()),
                            const SizedBox(width: 9),
                            _key(
                                child:
                                    Text('0', style: F.khand(24, color: Y2.ink)),
                                onTap: () => _tapDigit('0')),
                            const SizedBox(width: 9),
                            _key(
                                child: const Icon(Icons.backspace_outlined,
                                    size: 20, color: Y2.muted),
                                onTap: _backspace,
                                alt: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                PrimaryButton2(
                  label: S.t('Verify & sign in', 'पडताळा आणि साइन इन'),
                  busy: _busy,
                  enabled: ready,
                  onTap: ready ? _verify : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _otpBox(int index) {
    final filled = index < _code.length;
    final active = index == _code.length && !_busy;
    final border = _error
        ? Y2.red
        : (filled || active)
            ? Y2.accent
            : Y2.line;
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Y2.card,
        border: Border.all(color: border, width: 1.5),
        borderRadius: BorderRadius.circular(11),
      ),
      child: filled
          ? Text(_code[index],
              style: F.mono(26, color: _error ? Y2.red : Y2.ink))
          // Active box shows a slim caret; idle empty boxes show nothing.
          : active
              ? Container(width: 2, height: 24, color: Y2.accent)
              : const SizedBox.shrink(),
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

  Widget _key(
          {required Widget child, required VoidCallback onTap, bool alt = false}) =>
      Expanded(
        child: Pressable2(
          haptic: false, // digit/backspace handlers fire their own haptic
          scale: 0.94,
          onTap: onTap,
          child: Container(
            height: 46,
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
