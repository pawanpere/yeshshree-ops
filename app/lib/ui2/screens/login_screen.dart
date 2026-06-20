import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/polish2.dart';

/// Pilot entry login (username + password → /auth/login). Full-viewport,
/// responsive (centered card). On success the session goes live and the entry
/// advances to the role picker. NOT inside the phone frame.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the CTA + inline hints on every keystroke in either field.
    for (final c in [_user, _pass]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  // Both fields are required and must be valid before Sign in is tappable: a
  // login-shaped username and a non-trivial password (≥6, not all-whitespace).
  bool get _userValid => V.loginUsername(_user.text);
  bool get _passValid => V.password(_pass.text);
  bool get _canSignIn => _userValid && _passValid;

  Future<void> _login() async {
    // Hard-block: never submit while invalid (the button is also disabled).
    if (_busy || !_canSignIn) return;
    final u = _user.text.trim();
    final p = _pass.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Bind the device first so authed reads/writes carry the station device.
      await ref.read(authProvider.notifier).setDeviceKey('gate-kiosk-1');
      await ref.read(authProvider.notifier).login(u, p);
      // Entry watches authProvider and advances — nothing else to do.
    } on DioException catch (e) {
      final ex = ApiException.from(e);
      if (!mounted) return;
      setState(() => _error = ex.code == 'UNKNOWN' || ex.code == 'OFFLINE'
          ? S.t('Wrong username or password, or backend offline',
              'चुकीचे वापरकर्तानाव/पासवर्ड, किंवा बॅकएंड बंद')
          : ex.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = S.t('Something went wrong', 'काहीतरी चूक झाली'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Y2.navy,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Y2.screen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _brand(),
                const SizedBox(height: 22),
                _label(S.t('USERNAME', 'वापरकर्तानाव')),
                _field(_user,
                    hint: 'admin',
                    formatters: V.usernameInput,
                    // Show the rule only once they've typed something invalid.
                    error: _user.text.trim().isNotEmpty && !_userValid
                        ? S.t('3–64 chars: a–z, 0–9, dot or underscore',
                            '३–६४ अक्षरे: a–z, 0–9, टिंब किंवा अंडरस्कोर')
                        : null),
                const SizedBox(height: 14),
                _label(S.t('PASSWORD', 'पासवर्ड')),
                _field(_pass,
                    obscure: _obscure,
                    onSubmit: (_) => _login(),
                    error: _pass.text.isNotEmpty && !_passValid
                        ? S.t('Password must be at least 6 characters',
                            'पासवर्ड किमान ६ अक्षरांचा हवा')
                        : null,
                    trailing: GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: Y2.muted),
                    )),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: F.hind(12, color: Y2.red),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                PrimaryButton2(
                  label: S.t('Sign in', 'साइन इन'),
                  busy: _busy,
                  enabled: _canSignIn,
                  onTap: _login,
                ),
                const SizedBox(height: 12),
                Text('demo · admin / demo1234',
                    textAlign: TextAlign.center,
                    style: F.mono(10, color: Y2.muted2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() => Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.accent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Text('Y',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Khand',
                    fontWeight: FontWeight.w700,
                    fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YESHSHREE OPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.khand(20, ls: 0.5, color: Y2.ink)),
                Text(S.t('Plant 1117 · sign in', 'प्लांट 1117 · साइन इन'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(11, color: Y2.muted)),
              ],
            ),
          ),
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: F.hind(10, w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
      );

  Widget _field(TextEditingController c,
          {String? hint,
          bool obscure = false,
          Widget? trailing,
          ValueChanged<String>? onSubmit,
          List<TextInputFormatter>? formatters,
          String? error}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Y2.card,
              // Red hairline when the field is filled-but-invalid.
              border: Border.all(color: error != null ? Y2.red : Y2.line),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: c,
                    obscureText: obscure,
                    onSubmitted: onSubmit,
                    inputFormatters: formatters,
                    style: F.hind(15, color: Y2.ink),
                    cursorColor: Y2.accent,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: F.hind(15, color: Y2.muted2),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          if (error != null) FieldHint(error),
        ],
      );
}
