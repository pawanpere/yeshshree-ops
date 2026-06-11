/// Planning cockpit (scr-p-home): KPI grid from /dashboards/overview plus the
/// action queue — schedules, config, holds, approvals, unmatched gate entries.
/// Web-dashboard feel: content centered, max width ~900.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../widgets/common.dart';

class PlanningHomeScreen extends ConsumerStatefulWidget {
  const PlanningHomeScreen({super.key});

  @override
  ConsumerState<PlanningHomeScreen> createState() =>
      _PlanningHomeScreenState();
}

class _PlanningHomeScreenState extends ConsumerState<PlanningHomeScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    try {
      final r = await Api.dio.get('/dashboards/overview');
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('Planning — today', 'नियोजन — आज')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AsyncBody<Map<String, dynamic>>(
                future: _future,
                onRetry: _reload,
                builder: (context, o) {
                  final anomalies =
                      Map<String, dynamic>.from(o['open_anomalies'] as Map? ??
                          const {'total': 0, 'hard': 0});
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    SizedBox(
                        width: 200,
                        child: KpiCard(
                            label: S.t('Approvals pending',
                                'मंजुरी प्रलंबित'),
                            value: '${o['approvals_pending'] ?? 0}')),
                    SizedBox(
                        width: 200,
                        child: KpiCard(
                            label: S.t('Open anomalies', 'खुल्या विसंगती'),
                            value: '${anomalies['total'] ?? 0}',
                            delta: '${anomalies['hard'] ?? 0} '
                                '${S.t('hard', 'गंभीर')}',
                            deltaBad: (anomalies['hard'] as num? ?? 0) > 0)),
                    SizedBox(
                        width: 200,
                        child: KpiCard(
                            label: S.t('Unmatched gate entries',
                                'जुळल्या नसलेल्या गेट नोंदी'),
                            value: '${o['unmatched_gate_entries'] ?? 0}')),
                    SizedBox(
                        width: 200,
                        child: KpiCard(
                            label: S.t('Holds open', 'खुले होल्ड्स'),
                            value: '${o['holds_open'] ?? 0}')),
                  ]);
                },
              ),
              const SizedBox(height: 16),
              Text(S.t('Go to', 'येथे जा'),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              AppCard(
                title: S.t('Release a schedule', 'वेळापत्रक प्रसिद्ध करा'),
                body: S.t(
                    'Diff vs last version, sanity checks, one-tap release.',
                    'मागील आवृत्तीशी तुलना, तपासण्या, एका टॅपमध्ये प्रसिद्धी.'),
                kind: 'info',
                onTap: () => context.push('/planning/schedule'),
              ),
              AppCard(
                title: S.t('Admin & config', 'अ‍ॅडमिन व कॉन्फिग'),
                body: S.t(
                    'Splits, reason codes, mills, tolerances, calendar, settings.',
                    'स्प्लिट्स, कारण कोड, मिल्स, सहनशीलता, दिनदर्शिका, सेटिंग्ज.'),
                kind: 'info',
                onTap: () => context.push('/planning/config'),
              ),
              AppCard(
                title: S.t('Confirmation holds', 'नोंद होल्ड्स'),
                body: S.t('Supervisor posts waiting for a production order.',
                    'उत्पादन ऑर्डरच्या प्रतीक्षेतील नोंदी.'),
                kind: 'warn',
                onTap: () => context.push('/supervisor/holds'),
              ),
              AppCard(
                title: S.t('Approvals', 'मंजुरी'),
                body: S.t('Corrections, waivers and overrides pending.',
                    'दुरुस्त्या, सवलती व ओव्हरराइड प्रलंबित.'),
                kind: 'info',
                onTap: () => context.push('/mgmt/approvals'),
              ),
              AppCard(
                title: S.t('Unmatched gate entries', 'जुळल्या नसलेल्या गेट नोंदी'),
                body: S.t('Gate entries with no matching document yet.',
                    'अद्याप दस्तऐवज न जुळलेल्या गेट नोंदी.'),
                kind: 'warn',
                onTap: () => context.push('/gate/unmatched'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
