import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Dispatch detail — prototype screen [20]. Parts to load for a delivery order.
/// The DO chip + customer reflect the order stashed by the dispatch list. The
/// vehicle row is a working Picker2 (static transport options). Confirming
/// posts the dispatch (POST /dispatches) through the retry queue, stashes the
/// generated gate pass for the result screen, then replaces to the gate pass.
class Ui2DispatchDetailScreen extends ConsumerStatefulWidget {
  const Ui2DispatchDetailScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2DispatchDetailScreen> createState() =>
      _Ui2DispatchDetailScreenState();
}

class _Ui2DispatchDetailScreenState
    extends ConsumerState<Ui2DispatchDetailScreen> {
  PhoneNav get nav => widget.nav;

  // Static transport options (no master endpoint for vehicles in the demo).
  static const _vehicles = <(String, String)>[
    ('MH12 GH 7781', 'Tempo'),
    ('MH14 AB 2210', 'Truck'),
  ];

  String _veh = _vehicles.first.$1;
  String _vehType = _vehicles.first.$2;
  bool _submitting = false;

  String get _do => '${Ui2Flow.get<String>('dispatch.do') ?? 'DO-3391'}';
  String get _customer =>
      '${Ui2Flow.get<String>('dispatch.customer') ?? 'Bajaj Auto'}';

  String _vehTypeLabel(String t) =>
      t == 'Truck' ? S.t('Truck', 'ट्रक') : S.t('Tempo', 'टेम्पो');

  void _pickVehicle() {
    nav.overlay(Picker2Sheet<String>(
      title: S.t('Vehicle', 'वाहन'),
      options: [
        for (final v in _vehicles)
          Picker2Option<String>(v.$1, v.$1, sub: _vehTypeLabel(v.$2)),
      ],
      onPick: (plate) {
        final picked = _vehicles.firstWhere((v) => v.$1 == plate);
        setState(() {
          _veh = picked.$1;
          _vehType = picked.$2;
        });
        nav.hideOverlay();
      },
    ));
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // client_ref is auto-added by Data.submit (idempotency key).
    final res = await Data.submit(
      ref,
      '/dispatches',
      {
        'customer_id': 1,
        'vehicle_no': _veh,
        'lines': <Map<String, dynamic>>[],
      },
      label: '${S.t('Dispatch', 'डिस्पॅच')} $_do',
    );
    if (!mounted) return;
    // Surface a real failure, but still proceed for the demo so the flow works.
    if (res.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error?.message ??
              S.t('Could not post — saved for the demo',
                  'पोस्ट करता आले नाही — डेमोसाठी जतन केले')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      HapticFeedback.mediumImpact();
    }
    // Derive the gate pass id from the server response when available.
    final data = res.data;
    final pass = (data?['gate_pass'] ?? data?['gate_pass_no'] ?? data?['id'])
            ?.toString() ??
        'GP-2208';
    Ui2Flow.set('dispatch.pass', pass);
    Ui2Flow.set('dispatch.vehicle', _veh);
    nav.replace(ScreenId.gatePass);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + DO chip + customer
        ScreenHeader2(
          title: _customer.toUpperCase(),
          onBack: nav.pop,
          chip: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Y2.lineSoft,
              border: Border.all(color: const Color(0xFFD2DAE6)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(_do, style: F.mono(12, color: Y2.accent)),
          ),
        ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(S.t('PARTS TO LOAD', 'लोड करायचे भाग'),
                        style: F.hind(11,
                            w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                    Text(S.t('1 part', '1 भाग'),
                        style: F.hind(11, color: Y2.muted)),
                  ],
                ),
                const SizedBox(height: 11),
                // Part row
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    borderRadius: BorderRadius.circular(Y2.rRow),
                    border: Border.all(color: Y2.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.t('Front fork 4521', 'फ्रंट फोर्क 4521'),
                                style: F.hind(14,
                                    w: FontWeight.w600, color: Y2.ink)),
                            Text(
                                S.t('picked from WIP · Line A',
                                    'WIP मधून घेतले · Line A'),
                                style: F.hind(11, color: Y2.muted)),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('320', style: F.mono(17, color: Y2.ink)),
                          const SizedBox(width: 3),
                          Text(S.t('pc', 'pc'),
                              style: F.hind(11, color: Y2.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                // Vehicle row — tappable picker (reads as a select)
                Pressable2(
                  onTap: _pickVehicle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Y2.lineSoft,
                      borderRadius: BorderRadius.circular(Y2.rRow),
                      border: Border.all(color: Y2.line),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(S.t('Vehicle · tap to change',
                                      'वाहन · बदलण्यासाठी टॅप करा'),
                                  style: F.hind(11,
                                      w: FontWeight.w400, color: Y2.muted)),
                              Text(
                                  '$_veh · ${_vehTypeLabel(_vehType)}',
                                  style: F.hind(14,
                                      w: FontWeight.w600, color: Y2.ink)),
                            ],
                          ),
                        ),
                        const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                // Dashed info box
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x0D1D4ED8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBCD0F5)),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: F.hind(12, color: Y2.body, height: 1.4),
                      children: [
                        TextSpan(
                            text: S.t('On confirm: generates a ',
                                'पुष्टी केल्यावर: एक ')),
                        TextSpan(
                            text: S.t('gate pass', 'गेट पास'),
                            style: F.hind(12,
                                w: FontWeight.w700, color: Y2.body)),
                        TextSpan(
                            text: S.t(
                                ', posts the delivery to SAP, and reduces stock. Works offline — queues if no signal.',
                                ' तयार होतो, डिलिव्हरी SAP मध्ये पोस्ट होते आणि स्टॉक कमी होतो. ऑफलाइन चालते — सिग्नल नसल्यास रांगेत ठेवते.')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Footer action
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: _submitting
                ? S.t('Generating…', 'तयार करत आहे…')
                : S.t('Confirm & generate gate pass',
                    'पुष्टी करा आणि गेट पास तयार करा'),
            busy: _submitting,
            onTap: _confirm,
          ),
        ),
      ],
    );
  }
}
