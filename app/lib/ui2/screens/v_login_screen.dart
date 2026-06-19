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

/// Vendor sign-in — prototype screen [37]. Editable mobile-number field; tapping
/// "Send code" requests a real OTP (failure ignored for the demo), stashes the
/// phone for the OTP screen, and advances to OTP entry. No back, no tabs.
class Ui2VLoginScreen extends ConsumerStatefulWidget {
  const Ui2VLoginScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2VLoginScreen> createState() => _Ui2VLoginScreenState();
}

class _Ui2VLoginScreenState extends ConsumerState<Ui2VLoginScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  PhoneNav get nav => widget.nav;

  String get _digits => _ctrl.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleLang() => setState(
      () => S.lang.value = S.lang.value == 'mr' ? 'en' : 'mr');

  Future<void> _sendCode() async {
    if (_busy) return;
    final phone = _digits.isEmpty ? '98XXX XXX21' : _ctrl.text.trim();
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).requestOtp(phone);
    } catch (_) {
      // Demo: ignore the failure and still move the user to OTP entry.
    }
    Ui2Flow.set('vendor.phone', phone);
    if (mounted) nav.replace(ScreenId.vOtp);
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Column(
      children: [
        const StatusBar2(),
        // ---- Top bar: language toggle (so a Marathi-first user can switch) ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Pressable2(
                onTap: _toggleLang,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD2DAE6)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(S.t('EN', 'मराठी'),
                      style: F.hind(11, w: FontWeight.w500, color: Y2.ink)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 26, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(S.t('VENDOR PORTAL', 'व्हेंडर पोर्टल'),
                    style: F.khand(24, ls: 0.5, height: 1, color: Y2.ink)),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(S.t('SUPPLIER SIGN-IN', 'पुरवठादार साइन-इन'),
                      style: F.mono(12, color: Y2.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text(S.t('MOBILE NUMBER', 'मोबाइल नंबर'),
                      style: F.hind(13,
                          w: FontWeight.w600,
                          ls: 0.4,
                          color: const Color(0xFF6B7689))),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: focused ? Y2.accent : Y2.line,
                        width: focused ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Text('+91', style: F.mono(16, color: Y2.muted)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9 ]')),
                            LengthLimitingTextInputFormatter(15),
                          ],
                          style: F.mono(18, color: Y2.ink),
                          cursorColor: Y2.accent,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '98XXX XXX21',
                            hintStyle: F.mono(18, color: Y2.muted2),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      S.t(
                          "We'll send a one-time code by SMS. Only numbers registered as a supplier contact can sign in.",
                          'आम्ही SMS ने एक-वेळ कोड पाठवू. फक्त पुरवठादार संपर्क म्हणून नोंदवलेले नंबरच साइन-इन करू शकतात.'),
                      style: F.hind(12, color: Y2.muted, height: 1.5)),
                ),
                const Spacer(),
                PrimaryButton2(
                  label: S.t('Send code', 'कोड पाठवा'),
                  busy: _busy,
                  enabled: _digits.isNotEmpty,
                  onTap: _sendCode,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
