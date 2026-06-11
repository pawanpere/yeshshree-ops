/// Station PIN switch — shared shop-floor devices. One-time device-key setup
/// (e.g. gate-kiosk-1) is stored locally; after that, any user on this station
/// switches in with username + 4-digit PIN. Backend rejects with STATION_MISMATCH
/// etc. — the envelope message is shown verbatim.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_state.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

class PinSwitchScreen extends ConsumerStatefulWidget {
  const PinSwitchScreen({super.key});

  @override
  ConsumerState<PinSwitchScreen> createState() => _PinSwitchScreenState();
}

class _PinSwitchScreenState extends ConsumerState<PinSwitchScreen> {
  final _deviceKey = TextEditingController();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _deviceKey.dispose();
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _saveDeviceKey() async {
    final key = _deviceKey.text.trim();
    if (key.isEmpty) return;
    await ref.read(authProvider.notifier).setDeviceKey(key);
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
          .pinSwitch(_username.text.trim(), _pin.text);
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
    final session = ref.watch(authProvider);
    final deviceKey = session.deviceKey;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Station PIN login', 'स्टेशन PIN लॉगिन'))),
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
                      title: S.t('Could not switch', 'बदल करता आला नाही'),
                      body: error.message,
                    ),
                  if (deviceKey == null) ...[
                    AlertBanner(
                      kind: 'info',
                      title: S.t('One-time device setup',
                          'एकदाच करायची डिव्हाइस नोंदणी'),
                      body: S.t(
                          'This device is not registered as a station yet. Enter the device key given by admin (e.g. gate-kiosk-1).',
                          'हे डिव्हाइस अजून स्टेशन म्हणून नोंदलेले नाही. ॲडमिनने दिलेली डिव्हाइस की टाका (उदा. gate-kiosk-1).'),
                    ),
                    TextField(
                      controller: _deviceKey,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: S.t('Device key', 'डिव्हाइस की'),
                        hintText: 'gate-kiosk-1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _saveDeviceKey,
                      child: Text(S.t('Save device key', 'डिव्हाइस की जतन करा')),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        StatusBadge(S.t('Device', 'डिव्हाइस'), kind: 'ok'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(deviceKey,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(authProvider.notifier)
                              .setDeviceKey(null),
                          child: Text(S.t('Change', 'बदला')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: S.t('PIN (4 digits)', 'PIN (4 अंक)'),
                        counterText: '',
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
                          : Text(S.t('Switch user', 'वापरकर्ता बदला')),
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
