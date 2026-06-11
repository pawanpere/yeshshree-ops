/// §11.3 offline gate backfill. Internet down at the gate? The truck still
/// proceeds: minimal entry (vehicle, driver, vendor as text) submitted ONLY
/// through the retry queue — it works in airplane mode by design and syncs
/// later. Completion (real document data) happens from the Unmatched folder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class BackfillScreen extends ConsumerStatefulWidget {
  const BackfillScreen({super.key});

  @override
  ConsumerState<BackfillScreen> createState() => _BackfillScreenState();
}

class _BackfillScreenState extends ConsumerState<BackfillScreen> {
  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  final _vendorText = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _vehicle.dispose();
    _driver.dispose();
    _vendorText.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    if (_vehicle.text.trim().isEmpty ||
        _driver.text.trim().isEmpty ||
        _vendorText.text.trim().isEmpty) {
      _toast(S.t('All three fields are required', 'तिन्ही रकाने आवश्यक आहेत'));
      return;
    }
    final body = {
      'client_ref': const Uuid().v4(),
      'vehicle_no': _vehicle.text.trim(),
      'driver_name': _driver.text.trim(),
      'vendor_name_text': _vendorText.text.trim(),
      'entered_at': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() => _submitting = true);
    try {
      final r = await ref.read(retryQueueProvider.notifier).post(
          '/gate-entries/backfill', body,
          label: 'Backfill ${_vehicle.text.trim()}');
      if (!mounted) return;
      if (r == null) {
        _toast(S.t('Queued — will sync when internet returns',
            'रांगेत — इंटरनेट आल्यावर सिंक होईल'));
      } else {
        _toast(S.t('Entry ${r['doc_no']} recorded — complete it from Unmatched',
            'नोंद ${r['doc_no']} झाली — Unmatched मधून पूर्ण करा'));
      }
      _vehicle.clear();
      _driver.clear();
      _vendorText.clear();
    } on ApiException catch (ex) {
      if (mounted) _toast(ex.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queued = ref.watch(retryQueueProvider);
    return Scaffold(
      appBar: AppBar(
          title: Text(S.t('Gate backfill · offline', 'गेट बॅकफिल · ऑफलाइन'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AlertBanner(
            kind: 'info',
            title: S.t('Internet down? This still works.',
                'इंटरनेट बंद आहे? तरीही हे चालते.'),
            body: S.t(
                'The truck proceeds now; this minimal entry is saved on the phone and synced automatically. Complete the entry later from the Unmatched folder.',
                'ट्रक आता पुढे जातो; ही किमान नोंद फोनवर साठवली जाते आणि आपोआप सिंक होते. नंतर Unmatched फोल्डरमधून नोंद पूर्ण करा.'),
          ),
          if (queued.isNotEmpty)
            AlertBanner(
                kind: 'warn',
                title: S.t('${queued.length} entry(ies) waiting to sync',
                    '${queued.length} नोंदी सिंकच्या प्रतीक्षेत'),
                body: queued.map((q) => q.label).join(' · ')),
          TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            decoration:
                InputDecoration(labelText: S.t('Vehicle no. *', 'वाहन क्र. *')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _driver,
            decoration: InputDecoration(
                labelText: S.t('Driver name *', 'चालकाचे नाव *')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vendorText,
            decoration: InputDecoration(
                labelText: S.t('Vendor name (as written) *',
                    'पुरवठादाराचे नाव (जसे लिहिले आहे) *'),
                helperText: S.t('Free text — matched to the master later',
                    'मोकळा मजकूर — नंतर मास्टरशी जुळवला जाईल')),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(S.t('Record entry — truck proceeds',
                    'नोंद करा — ट्रक पुढे जाऊ द्या')),
          ),
          const SizedBox(height: 8),
          Text(
              S.t('Saved with the actual gate time, not the sync time.',
                  'सिंक वेळ नव्हे, प्रत्यक्ष गेट वेळेसह जतन होते.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: YColors.muted)),
        ],
      ),
    );
  }
}
