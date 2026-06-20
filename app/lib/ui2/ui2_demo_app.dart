import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_state.dart';
import '../core/strings.dart';
import 'data/api2.dart';
import 'office_shell.dart';
import 'phone_shell.dart';
import 'roles.dart';
import 'screens/login_screen.dart';
import 'screens/role_picker_screen.dart';
import 'theme2.dart';
import 'tokens.dart';
import 'widgets/frame.dart';
import 'widgets/lang_toggle.dart';

/// The ui2 pilot app (mounted with `--dart-define=UI2_MODE=true`). Flow:
/// login → pick a role → see ONLY that role's screens. Floor + vendor roles run
/// in the phone shell (framed on desktop, full-screen on a real device);
/// management / planning / admin run in the responsive office shell.
class Ui2DemoApp extends StatelessWidget {
  const Ui2DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yeshshree Ops',
      debugShowCheckedModeBanner: false,
      theme: theme2(),
      // Wrap everything in a transparent Material so Text never paints the
      // "missing Material ancestor" yellow underline (our shells are bare
      // Containers/Columns, not Scaffolds). Transparency keeps each screen's
      // own background.
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
      home: const _Entry(),
    );
  }
}

class _Entry extends ConsumerStatefulWidget {
  const _Entry();
  @override
  ConsumerState<_Entry> createState() => _EntryState();
}

class _EntryState extends ConsumerState<_Entry> {
  bool _restored = false;
  String? _devRole;

  @override
  void initState() {
    super.initState();
    final q = Uri.base.queryParameters;
    final lang = q['lang'];
    if (lang == 'en' || lang == 'mr') S.lang.value = lang!;
    _devRole = q['role'];
    // Apply the dev-bypass demo session AFTER the persisted session has loaded,
    // so the async _restore() can't clobber it. (A persisted logged-out/expired
    // session would otherwise overwrite the demo sign-in and leave the splash
    // spinning forever for ?role= deep-links — the "keeps buffering" bug.)
    ref.read(authProvider.notifier).whenRestored.then((_) {
      if (!mounted) return;
      _maybeDevBypass(_devRole);
      setState(() => _restored = true);
    });
  }

  /// Dev/QA deep-link for previewing roles without a backend or typing the
  /// login: `?role=<roleName>` signs in with a local demo session and jumps
  /// straight to that role's shell; `?role=picker` stops at the role picker.
  /// With no `role` param the real (network) login screen is shown.
  void _maybeDevBypass(String? role) {
    if (role == null) return;
    // Offline preview: all data is demo, no network → the live backend's 401 on the
    // fake token can never force-logout and bounce us back to the picker.
    Data.demoMode = true;
    ref.read(authProvider.notifier).devSignIn();
    if (role == 'picker') return;
    for (final r in Role.values) {
      if (r.name == role) {
        ref.read(activeRoleProvider.notifier).state = r;
        break;
      }
    }
  }

  Future<void> _signOut() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) ref.read(activeRoleProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    // Any logout (incl. a forced 401 logout) clears the picked role, so a fresh
    // login always returns to the picker — never the previous user's shell.
    ref.listen(authProvider, (prev, next) {
      if (prev != null && prev.loggedIn && !next.loggedIn) {
        ref.read(activeRoleProvider.notifier).state = null;
      }
    });

    final session = ref.watch(authProvider);
    final role = ref.watch(activeRoleProvider);

    // Rebuild the WHOLE app subtree whenever the language flips, so every visible
    // S.t(...) string updates instantly (no more "navigate away and back"). The
    // content is constructed INSIDE the builder — fresh widgets, not a captured
    // const — so descendants actually re-render on a language change.
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, _, __) {
        // Splash until the persisted session resolves (and while a dev-bypass
        // login is in flight) so a returning user never sees the login form flash.
        if (!_restored || (_devRole != null && !session.loggedIn)) {
          return _splash();
        }

        if (!session.loggedIn) return LoginScreen();

        if (role == null) {
          final allowed = rolesForAccount(session.role);
          // Account entitled to exactly one role → skip the picker (locked role).
          if (allowed.length == 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && ref.read(activeRoleProvider) == null) {
                ref.read(activeRoleProvider.notifier).state = allowed.first;
              }
            });
            return _splash();
          }
          return RolePickerScreen(roles: allowed, onSignOut: _signOut);
        }

        final spec = kRoles[role]!;
        if (spec.isOffice) {
          return OfficeShell(key: ValueKey('office-$role'), spec: spec);
        }
        return _PhoneRoleScaffold(key: ValueKey('phone-$role'), spec: spec);
      },
    );
  }

  Widget _splash() => Container(
        color: Y2.navy,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: Colors.white),
        ),
      );
}

/// Wraps the phone shell for a floor/vendor role with a slim app bar (role name
/// + language + switch role + sign out). Framed on desktop, full on mobile.
class _PhoneRoleScaffold extends ConsumerWidget {
  const _PhoneRoleScaffold({super.key, required this.spec});
  final RoleSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggleLang() => toggleLanguage(context);
    void switchRole() => ref.read(activeRoleProvider.notifier).state = null;
    Future<void> signOut() async {
      await ref.read(authProvider.notifier).logout();
      ref.read(activeRoleProvider.notifier).state = null;
    }

    final shell = PhoneShell(tabs: spec.tabs);
    return Container(
      color: Y2.navy,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          // The phone frame is a desktop-WEB preview affordance only. On a real
          // native device (Android tablet/phone, iOS) the app runs full-screen —
          // never framed, even on a wide tablet. kIsWeb is false on native.
          final framed = kIsWeb && c.maxWidth >= 760;
          return Column(
            children: [
              _topBar(toggleLang, switchRole, signOut),
              Expanded(
                child: framed
                    ? Center(child: PhoneFrame2(child: shell))
                    : ColoredBox(color: Y2.screen, child: shell),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _topBar(
          VoidCallback lang, VoidCallback switchRole, VoidCallback signOut) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Row(
          children: [
            Icon(spec.icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(S.t(spec.en, spec.mr),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Khand',
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      letterSpacing: 0.5)),
            ),
            _chip(S.lang.value == 'mr' ? 'EN' : 'मराठी', lang),
            const SizedBox(width: 7),
            _chip(S.t('Role', 'भूमिका'), switchRole),
            const SizedBox(width: 7),
            _iconBtn(Icons.logout, signOut),
          ],
        ),
      );

  Widget _chip(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Hind',
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}
