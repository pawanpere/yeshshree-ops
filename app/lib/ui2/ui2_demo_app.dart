import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_state.dart';
import '../core/strings.dart';
import 'nav.dart';
import 'phone_shell.dart';
import 'screen_registry.dart';
import 'theme2.dart';
import 'tokens.dart';
import 'widgets/frame.dart';

/// Backend-free preview harness for the `ui2` rebuild. Mounted with
/// `--dart-define=UI2_MODE=true`. Hosts the live [PhoneShell] inside the device
/// frame, with a dev jump-nav to land on any screen and an EN/Marathi toggle.
/// Deep-link a state for screenshot QA: `?screen=<id>&lang=mr&sheet=correction`.
class Ui2DemoApp extends StatelessWidget {
  const Ui2DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yeshshree Ops · ui2',
      debugShowCheckedModeBanner: false,
      theme: theme2(),
      home: const _Gallery(),
    );
  }
}

class _Gallery extends ConsumerStatefulWidget {
  const _Gallery();
  @override
  ConsumerState<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends ConsumerState<_Gallery> {
  ScreenId _jump = ScreenId.home;
  SheetId? _initSheet;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    final q = Uri.base.queryParameters;
    _jump = screenIdFromSlug(q['screen'] ?? '') ?? ScreenId.home;
    if (q['sheet'] == 'correction') _initSheet = SheetId.correction;
    final lang = q['lang'];
    if (lang == 'en' || lang == 'mr') S.lang.value = lang!;
    _bootstrapSession();
  }

  /// Connected-demo session: register the seeded device and sign in a seeded
  /// supervisor so authed backend reads/writes work. Fire-and-forget and
  /// harmless if the backend is down — reads fall back to DEMO data.
  void _bootstrapSession() {
    // Sign in as the seeded 'admin' (broadest role) so every screen's reads and
    // writes are authorized in the connected demo.
    final auth = ref.read(authProvider.notifier);
    auth
        .setDeviceKey('gate-kiosk-1')
        .then((_) => auth.login('admin', 'demo1234'))
        .catchError((_) {});
  }

  void _goto(ScreenId id) => setState(() {
        _jump = id;
        _initSheet = null;
        _rev++;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Y2.navy,
      body: SafeArea(
        child: Column(
          children: [
            _toolbar(),
            Expanded(
              child: Center(
                child: PhoneFrame2(
                  child: PhoneShell(
                    key: ValueKey('$_jump-$_rev'),
                    initial: _jump,
                    initialSheet: _initSheet,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() => Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Text('ui2',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Khand',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 1)),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<ScreenId>(
                  value: _jump,
                  isExpanded: true,
                  isDense: true,
                  borderRadius: BorderRadius.circular(10),
                  dropdownColor: Y2.navyDeep,
                  iconEnabledColor: Colors.white,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Hind',
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  items: [
                    for (final e in kScreens)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text('${e.group} · ${e.title}'),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) _goto(id);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            _langButton(),
          ],
        ),
      );

  Widget _langButton() => GestureDetector(
        onTap: () => setState(
            () => S.lang.value = S.lang.value == 'mr' ? 'en' : 'mr'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            S.lang.value == 'mr' ? 'EN' : 'मराठी',
            style: const TextStyle(
                color: Y2.navy,
                fontFamily: 'Hind',
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
        ),
      );
}
