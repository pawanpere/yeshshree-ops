/// Role-based home launcher (app map scr-o-home / scr-s-home): navy header with
/// name + plant/station subtitle, bell, overflow menu, retry-queue banner, and a
/// 2-column emoji tile grid that depends on role + station.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _whereLabel(Session s) {
    switch (s.station) {
      case 'gate':
        return S.t('Gate', 'गेट');
      case 'qc':
        return S.t('QC', 'क्यूसी');
      case 'store':
        return S.t('Store', 'स्टोअर');
      case 'ppc':
        return 'PPC';
    }
    switch (s.role) {
      case 'supervisor':
        return S.t('Supervisor', 'पर्यवेक्षक');
      case 'planning':
        return S.t('Planning', 'नियोजन');
      case 'management':
        return S.t('Management', 'व्यवस्थापन');
      case 'admin':
        return S.t('Admin', 'ॲडमिन');
      case 'plant_ops':
        return S.t('Plant operations', 'प्लांट ऑपरेशन्स');
    }
    return s.role ?? '';
  }

  List<Widget> _gateTiles(BuildContext context) => [
        TileButton(
          icon: '📷',
          title: S.t('Pending scans', 'प्रलंबित स्कॅन'),
          subtitle: S.t('Scanner inbox', 'स्कॅनर इनबॉक्स'),
          onTap: () => context.push('/gate/scans'),
        ),
        TileButton(
          icon: '🚪',
          title: S.t('Gate entry', 'गेट नोंद'),
          subtitle: S.t('Scan & log in', 'स्कॅन करून नोंदवा'),
          onTap: () => context.push('/gate/entry'),
        ),
        TileButton(
          icon: '🗂️',
          title: S.t('Unmatched', 'जुळणी नसलेले'),
          subtitle: S.t('POs to review', 'PO तपासणीसाठी'),
          onTap: () => context.push('/gate/unmatched'),
        ),
        TileButton(
          icon: '✍️',
          title: S.t('Offline backfill', 'ऑफलाइन नोंद'),
          subtitle: S.t('Paper log entry', 'कागदी नोंदी भरा'),
          onTap: () => context.push('/gate/backfill'),
        ),
        TileButton(
          icon: '🔔',
          title: S.t('Notifications', 'सूचना'),
          subtitle: S.t('Inbox', 'इनबॉक्स'),
          onTap: () => context.push('/notifications'),
        ),
      ];

  List<Widget> _qcTiles(BuildContext context) => [
        TileButton(
          icon: '📦',
          title: S.t('Inward QC / GR', 'इनवर्ड QC / GR'),
          subtitle: S.t('Receive & check', 'स्वीकारा व तपासा'),
          onTap: () => context.push('/qc/gr'),
        ),
        TileButton(
          icon: '🗂️',
          title: S.t('Unmatched', 'जुळणी नसलेले'),
          subtitle: S.t('POs to review', 'PO तपासणीसाठी'),
          onTap: () => context.push('/gate/unmatched'),
        ),
      ];

  List<Widget> _storeTiles(BuildContext context) => [
        TileButton(
          icon: '📤',
          title: S.t('Issue material', 'मटेरियल इश्यू'),
          subtitle: S.t('In-house / vendor', 'इन-हाउस / विक्रेता'),
          onTap: () => context.push('/store/issue'),
        ),
        TileButton(
          icon: '🚚',
          title: S.t('Dispatch', 'डिस्पॅच'),
          subtitle: S.t('To Bajaj', 'बजाजकडे'),
          onTap: () => context.push('/store/dispatch'),
        ),
        TileButton(
          icon: '🧾',
          title: S.t('Sale / billing', 'विक्री / बिलिंग'),
          subtitle: S.t('Confirm bills', 'बिले निश्चित करा'),
          ribbon: S.t('NEW', 'नवीन'),
          onTap: () => context.push('/store/billing'),
        ),
        TileButton(
          icon: '🗂️',
          title: S.t('Unmatched', 'जुळणी नसलेले'),
          subtitle: S.t('POs to review', 'PO तपासणीसाठी'),
          onTap: () => context.push('/gate/unmatched'),
        ),
      ];

  List<Widget> _supervisorTiles(BuildContext context) => [
        TileButton(
          icon: '✅',
          title: S.t('Confirm output', 'उत्पादन नोंदवा'),
          subtitle: S.t('Log output live', 'उत्पादन लगेच नोंदवा'),
          ribbon: S.t('DO NOW', 'आता करा'),
          onTap: () => context.push('/supervisor'),
        ),
        TileButton(
          icon: '🕘',
          title: S.t('History', 'इतिहास'),
          subtitle: S.t('Past confirmations', 'मागील नोंदी'),
          onTap: () => context.push('/supervisor/history'),
        ),
        TileButton(
          icon: '📊',
          title: S.t('Dashboards', 'डॅशबोर्ड'),
          subtitle: S.t('Plant at a glance', 'प्लांट एका दृष्टीत'),
          onTap: () => context.push('/mgmt'),
        ),
      ];

  List<Widget> _planningTiles(BuildContext context) => [
        TileButton(
          icon: '🗂️',
          title: S.t('Planning', 'नियोजन'),
          subtitle: S.t("Today's plan", 'आजची योजना'),
          onTap: () => context.push('/planning'),
        ),
        TileButton(
          icon: '📅',
          title: S.t('Schedule', 'वेळापत्रक'),
          subtitle: S.t('Lines & shifts', 'लाइन व शिफ्ट'),
          onTap: () => context.push('/planning/schedule'),
        ),
        TileButton(
          icon: '⚙',
          title: S.t('Config', 'कॉन्फिगरेशन'),
          subtitle: S.t('BOM & rates', 'BOM व दर'),
          onTap: () => context.push('/planning/config'),
        ),
        TileButton(
          icon: '⏸',
          title: S.t('Holds (PPC)', 'होल्ड (PPC)'),
          subtitle: S.t('Pause lines', 'लाइन थांबवा'),
          onTap: () => context.push('/supervisor/holds'),
        ),
        TileButton(
          icon: '✅',
          title: S.t('Approvals', 'मंजुरी'),
          subtitle: S.t('Debits & waivers', 'डेबिट व माफी'),
          onTap: () => context.push('/mgmt/approvals'),
        ),
      ];

  List<Widget> _managementTiles(BuildContext context) => [
        TileButton(
          icon: '📊',
          title: S.t('Dashboards', 'डॅशबोर्ड'),
          subtitle: S.t('Plant at a glance', 'प्लांट एका दृष्टीत'),
          onTap: () => context.push('/mgmt'),
        ),
        TileButton(
          icon: '✅',
          title: S.t('Approvals', 'मंजुरी'),
          subtitle: S.t('Debits & waivers', 'डेबिट व माफी'),
          onTap: () => context.push('/mgmt/approvals'),
        ),
        TileButton(
          icon: '⚐',
          title: S.t('Anomalies', 'विसंगती'),
          subtitle: S.t('Flags to review', 'तपासणीसाठी फ्लॅग'),
          onTap: () => context.push('/mgmt/anomalies'),
        ),
      ];

  Widget _grid(List<Widget> tiles) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.3,
        children: tiles,
      );

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: YColors.muted,
              letterSpacing: .5),
        ),
      );

  List<Widget> _tilesForRole(BuildContext context, Session session) {
    switch (session.role) {
      case 'admin':
        return [
          _section(S.t('Gate', 'गेट')),
          _grid(_gateTiles(context)),
          _section(S.t('QC', 'क्यूसी')),
          _grid(_qcTiles(context)),
          _section(S.t('Store', 'स्टोअर')),
          _grid(_storeTiles(context)),
          _section(S.t('Supervisor', 'पर्यवेक्षक')),
          _grid(_supervisorTiles(context)),
          _section(S.t('Planning', 'नियोजन')),
          _grid(_planningTiles(context)),
          _section(S.t('Management', 'व्यवस्थापन')),
          _grid(_managementTiles(context)),
        ];
      case 'supervisor':
        return [_grid(_supervisorTiles(context))];
      case 'planning':
        return [_grid(_planningTiles(context))];
      case 'management':
        return [_grid(_managementTiles(context))];
      default: // plant_ops (and any unknown role): tiles depend on station
        switch (session.station) {
          case 'gate':
            return [_grid(_gateTiles(context))];
          case 'qc':
            return [_grid(_qcTiles(context))];
          default: // store, ppc or no station
            return [_grid(_storeTiles(context))];
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider);
    final queue = ref.watch(retryQueueProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${S.t('Hello', 'नमस्कार')}, ${session.fullName ?? ''}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${S.t('Plant 1117', 'प्लांट 1117')} · ${_whereLabel(session)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: S.t('Notifications', 'सूचना'),
            onPressed: () => context.push('/notifications'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'pin':
                  context.push('/pin');
                case 'logout':
                  ref.read(authProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(S.t('Switch user (PIN)', 'वापरकर्ता बदला (PIN)')),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Text(S.t('Logout', 'लॉगआउट')),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (queue.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AlertBanner(
                            kind: 'warn',
                            title: S.t(
                                '${queue.length} entries waiting to sync',
                                '${queue.length} नोंदी सिंक होण्याच्या प्रतीक्षेत'),
                            body: S.t(
                                'Saved on this phone — they will post when the network returns.',
                                'या फोनवर जतन केल्या आहेत — नेटवर्क आल्यावर पाठवल्या जातील.'),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(retryQueueProvider.notifier).drain(),
                          child: Text(S.t('Sync now', 'आता सिंक करा')),
                        ),
                      ],
                    ),
                  ..._tilesForRole(context, session),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
