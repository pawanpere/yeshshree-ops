import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
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
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _identityHeader(wide: false),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel(S.t('PREFERENCES', 'प्राधान्ये')),
                _preferenceRows(),
                const SizedBox(height: 16),
                _sectionLabel(S.t('ACCOUNT', 'खाते')),
                _accountRows(),
                const SizedBox(height: 16),
                _sectionLabel(S.t('ABOUT', 'विषयी')),
                _aboutRows(),
              ],
            ),
          ),
        ),
        _signOutFooter(),
      ],
    );
  }

  // ---- desktop layout ----
  //
  // No StatusBar2 device chrome. The identity header stays as the screen's own
  // header; the settings sections are centered at a comfortable reading width and
  // laid out two-up (Preferences | Account+About) on wide boxes, with the
  // destructive Sign out pinned to the footer exactly as on phone.
  Widget _desktop() {
    return Column(
      children: [
        _identityHeader(wide: true),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: ResponsiveContent(
              maxWidth: 720,
              child: LayoutBuilder(builder: (context, c) {
                final twoCol = c.maxWidth >= 600;
                final prefs = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel(S.t('PREFERENCES', 'प्राधान्ये')),
                    _preferenceRows(),
                  ],
                );
                final accountAbout = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel(S.t('ACCOUNT', 'खाते')),
                    _accountRows(),
                    const SizedBox(height: 16),
                    _sectionLabel(S.t('ABOUT', 'विषयी')),
                    _aboutRows(),
                  ],
                );
                if (!twoCol) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      prefs,
                      const SizedBox(height: 16),
                      accountAbout,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: prefs),
                    const SizedBox(width: 20),
                    Expanded(child: accountAbout),
                  ],
                );
              }),
            ),
          ),
        ),
        _signOutFooter(),
      ],
    );
  }

  // ---- shared pieces ----

  // Identity strip (avatar + name + role/station). Shared by both layouts; the
  // phone path renders exactly as the original, desktop adds overflow safety so
  // the name/role can't overflow a wide row.
  Widget _identityHeader({required bool wide}) {
    final nameLine = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RAMESH K.',
            maxLines: wide ? 1 : null,
            overflow: wide ? TextOverflow.ellipsis : null,
            style: F.khand(18, ls: 0.3, height: 1, color: Y2.ink)),
        Text(S.t('Supervisor · $_station', 'सुपरवायझर · $_station'),
            maxLines: wide ? 1 : null,
            overflow: wide ? TextOverflow.ellipsis : null,
            style: F.hind(12, color: Y2.muted)),
      ],
    );
    return Container(
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
          wide ? Expanded(child: nameLine) : nameLine,
        ],
      ),
    );
  }

  Widget _preferenceRows() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      );

  Widget _accountRows() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      );

  Widget _aboutRows() => _row(
        Icons.info_outline_rounded,
        S.t('App version', 'अॅप आवृत्ती'),
        Text('4.2.1', style: F.mono(13, color: Y2.muted)),
        bold: false,
      );

  // Destructive: red-tinted, and confirms before signing out. Shared footer.
  Widget _signOutFooter() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
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
      );

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
