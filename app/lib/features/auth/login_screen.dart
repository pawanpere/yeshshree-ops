/// Login — navy hero ("Yeshshree Operations · Plant 1117"), username/password.
/// Errors surface the backend envelope via ApiException.message; a large clock
/// skew (§11.15) is explained as a device-clock problem instead of "login failed".
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(_username.text.trim(), _password.text);
      if (mounted) context.go('/home');
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: YColors.navy,
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 44, 20, 30),
              child: Column(
                children: [
                  const Text('🏭', style: TextStyle(fontSize: 34)),
                  const SizedBox(height: 8),
                  Text(
                    S.t('Yeshshree Operations', 'येशश्री ऑपरेशन्स'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.t('Plant 1117', 'प्लांट 1117'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null)
                        AlertBanner(
                          kind: 'danger',
                          title: S.t('Login failed', 'लॉगिन अयशस्वी'),
                          body: error.isClockSkew
                              ? S.t(
                                  'Your device clock looks wrong. Please set the correct date & time, then try again.',
                                  'तुमच्या डिव्हाइसचे घड्याळ चुकीचे दिसते. कृपया योग्य तारीख व वेळ सेट करा आणि पुन्हा प्रयत्न करा.')
                              : error.message,
                        ),
                      TextField(
                        controller: _username,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: S.t('Username', 'वापरकर्तानाव'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: S.t('Password', 'पासवर्ड'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(S.t('Login', 'लॉगिन')),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: () => context.push('/pin'),
                        child: Text(S.t('Station PIN login',
                            'स्टेशन PIN लॉगिन')),
                      ),
                      TextButton(
                        onPressed: () => context.push('/otp'),
                        child: Text(S.t('Vendor login (OTP)',
                            'विक्रेता लॉगिन (OTP)')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
