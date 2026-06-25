import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_state.dart';
import 'core/strings.dart';
import 'ui2/phone_shell.dart';
import 'ui2/theme2.dart';
import 'ui2/tokens.dart';

/// Full-screen native Android build of the `ui2` phone app.
///
/// Same screens as the `UI2_MODE` preview (`Ui2DemoApp`), but mounted
/// edge-to-edge with NO device-frame bezel and NO dev toolbar/jump-nav — so it
/// runs and feels like a real installed mobile app. The screens carry their own
/// status bar ([StatusBar2]) and tab bar, so we hide the system bars and skip
/// SafeArea, letting the app own the full surface.
///
/// Run with:  flutter run -t lib/ui2_fullscreen.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ProviderScope(child: Ui2FullScreenApp()));
}

class Ui2FullScreenApp extends StatelessWidget {
  const Ui2FullScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the EN/Marathi toggle flips S.lang.
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, _, __) => MaterialApp(
        title: 'Yeshshree Ops',
        debugShowCheckedModeBanner: false,
        theme: theme2(),
        home: const _Boot(),
      ),
    );
  }
}

/// Hosts the live [PhoneShell] full-screen. Mirrors the connected-demo session
/// bootstrap from [Ui2DemoApp]: register the seeded kiosk device and sign in a
/// seeded user so authed reads/writes work when the backend is up. Fire-and-
/// forget — if the backend is unreachable, every read falls back to clearly
/// marked DEMO data, so the app stays fully functional offline.
class _Boot extends ConsumerStatefulWidget {
  const _Boot();

  @override
  ConsumerState<_Boot> createState() => _BootState();
}

class _BootState extends ConsumerState<_Boot> {
  @override
  void initState() {
    super.initState();
    // Defer provider mutation past the first frame so we never write provider
    // state during build (the `!_dirty` ProviderScope assertion).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider.notifier);
      auth
          .setDeviceKey('gate-kiosk-1')
          .then((_) => auth.login('admin', 'demo1234'))
          .catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold gives the Material ancestor the screens' Switch/InkWell need, and
    // pins the light screen surface (theme2's scaffold default is navy, which is
    // only ever the area behind the preview frame).
    return const Scaffold(
      backgroundColor: Y2.screen,
      body: PhoneShell(),
    );
  }
}
