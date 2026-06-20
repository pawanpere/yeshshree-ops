import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/lang_toggle.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Profile / settings tab (Me) — prototype screen [27]. Language toggles
/// S.lang, notification sounds flips a local bool, My station opens a line
/// picker, Sync queue jumps to the Sync tab, and Sign out returns to sign-in.
class Ui2ProfileScreen extends StatefulWidget {
  const Ui2ProfileScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ProfileScreen> createState() => _Ui2ProfileScreenState();
}

class _Ui2ProfileScreenState extends State<Ui2ProfileScreen> {
  bool _soundsOn = true;
  String _station = 'Line A';

  PhoneNav get nav => widget.nav;

  void _toggleLang() => toggleLanguage(context);

  void _pickStation() {
    nav.overlay(Picker2Sheet<String>(
      title: S.t('My station', 'माझे स्टेशन'),
      options: const [
        Picker2Option('Line A', 'Line A', sub: 'Press 1–3'),
        Picker2Option('Line B', 'Line B', sub: 'Press 4–6'),
        Picker2Option('QC bench', 'QC bench'),
      ],
      onPick: (v) {
        setState(() => _station = v);
        nav.hideOverlay();
      },
    ));
  }

  void _changePin() {
    // The full Change-PIN flow lives in the auth stack; surfacing intent here
    // without importing another screen (router contract: screens stay decoupled).
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(S.t('Change PIN: enter your current PIN to continue',
          'PIN बदला: सुरू ठेवण्यासाठी सध्याचा PIN टाका')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Sign out is destructive mid-shift (queued writes may be pending), so confirm
  // first via an in-frame sheet before navigating to sign-in.
  void _confirmSignOut() {
    HapticFeedback.lightImpact();
    nav.overlay(_SignOutSheet(
      onConfirm: () {
        nav.hideOverlay();
        nav.go(ScreenId.signin);
      },
      onCancel: nav.hideOverlay,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Y2.lineSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD2DAE6)),
                ),
                child: Text('RK', style: F.khand(18, color: Y2.ink)),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RAMESH K.',
                      style: F.khand(18, ls: 0.3, height: 1, color: Y2.ink)),
                  Text(S.t('Supervisor · $_station', 'सुपरवायझर · $_station'),
                      style: F.hind(12, color: Y2.muted)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel(S.t('PREFERENCES', 'प्राधान्ये')),
                _row(
                  Icons.language_rounded,
                  S.t('Language', 'भाषा'),
                  Text(S.t('English', 'मराठी'),
                      style: F.hind(14, w: FontWeight.w600, color: Y2.accent)),
                  onTap: _toggleLang,
                ),
                const SizedBox(height: 9),
                _row(
                  Icons.factory_outlined,
                  S.t('My station', 'माझे स्टेशन'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_station, style: F.hind(14, color: Y2.muted)),
                    const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                  ]),
                  onTap: _pickStation,
                ),
                const SizedBox(height: 9),
                _row(
                  Icons.notifications_active_outlined,
                  S.t('Notification sounds', 'सूचना आवाज'),
                  Switch.adaptive(
                    value: _soundsOn,
                    activeThumbColor: Y2.accent,
                    onChanged: (v) => setState(() => _soundsOn = v),
                  ),
                  onTap: () => setState(() => _soundsOn = !_soundsOn),
                ),
                const SizedBox(height: 16),
                _sectionLabel(S.t('ACCOUNT', 'खाते')),
                _row(
                  Icons.lock_outline_rounded,
                  S.t('Change PIN', 'PIN बदला'),
                  const Icon(I2.chevronRight, size: 18, color: Y2.muted),
                  onTap: _changePin,
                ),
                const SizedBox(height: 9),
                _row(
                  I2.sync,
                  S.t('Sync queue', 'सिंक रांग'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(S.t('1 waiting', '1 प्रतीक्षेत'),
                        style: F.hind(14, color: Y2.muted)),
                    const Icon(I2.chevronRight, size: 18, color: Y2.muted),
                  ]),
                  onTap: () => nav.tab(2),
                ),
                const SizedBox(height: 16),
                _sectionLabel(S.t('ABOUT', 'विषयी')),
                _row(
                  Icons.info_outline_rounded,
                  S.t('App version', 'अॅप आवृत्ती'),
                  Text('4.2.1', style: F.mono(13, color: Y2.muted)),
                  bold: false,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          // Destructive: red-tinted, and confirms before signing out.
          child: Pressable2(
            onTap: _confirmSignOut,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: Y2.redTint,
                border: Border.all(color: Y2.redLine),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(S.t('Sign out', 'साइन आउट'),
                  style: F.hind(14, w: FontWeight.w600, color: Y2.red)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(label,
            style: F.hind(11, w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
      );

  Widget _row(IconData icon, String label, Widget trailing,
          {VoidCallback? onTap, bool bold = true}) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Y2.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: Y2.muted),
              const SizedBox(width: 11),
              Expanded(
                child: Text(label,
                    style: bold
                        ? F.hind(14, w: FontWeight.w600, color: Y2.ink)
                        : F.hind(13, color: Y2.muted)),
              ),
              trailing,
            ],
          ),
        ),
      );
}

/// In-frame confirmation sheet for the destructive Sign out action.
class _SignOutSheet extends StatelessWidget {
  const _SignOutSheet({required this.onConfirm, required this.onCancel});
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(S.t('Sign out?', 'साइन आउट करायचे?'),
              style: F.khand(18, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 6),
          Text(
              S.t('1 write is still waiting to sync. It stays queued and sends when you sign back in.',
                  '1 नोंद अजून सिंकच्या प्रतीक्षेत आहे. ती रांगेत राहील आणि पुन्हा साइन इन केल्यावर पाठवली जाईल.'),
              style: F.hind(12, color: Y2.muted, height: 1.5)),
          const SizedBox(height: 16),
          PrimaryButton2(
            label: S.t('Sign out', 'साइन आउट'),
            color: Y2.red,
            onTap: onConfirm,
          ),
          const SizedBox(height: 9),
          OutlineButton2(
            label: S.t('Stay signed in', 'साइन इन राहा'),
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}
