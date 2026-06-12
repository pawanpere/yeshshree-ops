import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'features/demo/demo_mode_app.dart';

const _demoMode = bool.fromEnvironment('DEMO_MODE');

void main() {
  runApp(const ProviderScope(child: YeshshreeApp()));
}

class YeshshreeApp extends ConsumerWidget {
  const YeshshreeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Rebuild on language switch (set at login from the user's profile).
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, _, __) {
        if (_demoMode) {
          return MaterialApp(
            title: 'Yeshshree Ops Demo',
            debugShowCheckedModeBanner: false,
            theme: yeshshreeTheme(),
            home: const DemoModeApp(),
          );
        }
        return MaterialApp.router(
          title: 'Yeshshree Ops',
          debugShowCheckedModeBanner: false,
          theme: yeshshreeTheme(),
          routerConfig: router,
        );
      },
    );
  }
}
