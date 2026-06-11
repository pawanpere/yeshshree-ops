/// Force-update wall (§11.15 version handshake). Shown when the app is below
/// /system/min-version. Calm, static copy; the download button is intentionally
/// inert (url_launcher is not a dependency yet) — the APK URL is shown so the
/// user can open it in a browser.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ForceUpdateScreen extends ConsumerStatefulWidget {
  const ForceUpdateScreen({super.key});

  @override
  ConsumerState<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends ConsumerState<ForceUpdateScreen> {
  Map<String, dynamic>? _info;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.dio.get('/system/min-version');
      if (!mounted) return;
      setState(() {
        _info = Map<String, dynamic>.from(r.data as Map);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.from(e);
        _loading = false;
      });
    }
  }

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: YColors.muted)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: YColors.navy)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(S.t('Update required', 'अपडेट आवश्यक'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AlertBanner(
                      kind: 'info',
                      title: S.t('A newer version is needed',
                          'नवी आवृत्ती आवश्यक आहे'),
                      body: S.t(
                          'This version of the app is too old to talk to the plant server. Please update — your data is safe on the server.',
                          'ॲपची ही आवृत्ती प्लांट सर्व्हरशी जोडण्यासाठी खूप जुनी आहे. कृपया अपडेट करा — तुमची माहिती सर्व्हरवर सुरक्षित आहे.'),
                    ),
                    if (error != null)
                      AlertBanner(
                        kind: 'danger',
                        title: S.t('Could not check version',
                            'आवृत्ती तपासता आली नाही'),
                        body: error.message,
                      ),
                    if (info != null)
                      AppCard(
                        title: S.t('Versions', 'आवृत्त्या'),
                        child: Column(
                          children: [
                            _versionRow(
                                S.t('Minimum required', 'किमान आवश्यक'),
                                (info['min_version'] ?? '—').toString()),
                            _versionRow(S.t('Latest available', 'नवीनतम उपलब्ध'),
                                (info['latest_version'] ?? '—').toString()),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: null,
                      child: Text(S.t('Download update', 'अपडेट डाउनलोड करा')),
                    ),
                    if (info != null && info['apk_url'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        S.t('Open this link in your browser to download:',
                            'डाउनलोडसाठी ही लिंक ब्राउझरमध्ये उघडा:'),
                        style: const TextStyle(
                            fontSize: 11, color: YColors.muted),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        info['apk_url'].toString(),
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: YColors.blue,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _load,
                      child: Text(S.t('Check again', 'पुन्हा तपासा')),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
