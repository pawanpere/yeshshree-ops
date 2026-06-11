/// Vendor OTP login — phone → code → in. While SMS is mocked, the backend
/// returns dev_code; we show it in a purple banner ("Demo code") so vendors can
/// be onboarded today. That banner disappears by itself once real SMS lands
/// (the API stops returning dev_code).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _devCode;
  ApiException? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code =
          await ref.read(authProvider.notifier).requestOtp(_phone.text.trim());
      if (mounted) {
        setState(() {
          _sent = true;
          _devCode = code;
        });
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .verifyOtp(_phone.text.trim(), _code.text.trim());
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
    final devCode = _devCode;
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Vendor login (OTP)', 'विक्रेता लॉगिन (OTP)'))),
      body: SingleChildScrollView(
        child: Center(
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
                      body: error.message,
                    ),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: S.t('Registered phone number',
                          'नोंदणीकृत फोन नंबर'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy ? null : _request,
                    child: Text(_sent
                        ? S.t('Resend code', 'कोड पुन्हा पाठवा')
                        : S.t('Send code', 'कोड पाठवा')),
                  ),
                  if (_sent) ...[
                    const SizedBox(height: 16),
                    if (devCode != null)
                      AlertBanner(
                        kind: 'purple',
                        title: S.t('Demo code: $devCode', 'डेमो कोड: $devCode'),
                        body: S.t(
                            'Shown only while SMS is in demo mode.',
                            'SMS डेमो मोडमध्ये असेपर्यंतच दाखवला जातो.'),
                      ),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autocorrect: false,
                      maxLength: 6,
                      onSubmitted: (_) => _verify(),
                      decoration: InputDecoration(
                        labelText: S.t('Enter code', 'कोड टाका'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : _verify,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(S.t('Verify & login', 'पडताळा व लॉगिन करा')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
