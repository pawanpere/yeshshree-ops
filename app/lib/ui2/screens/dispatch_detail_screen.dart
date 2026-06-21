import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';
import '../widgets/qty_field2.dart';

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

  // How much of the picked lot to dispatch. Not every lot ships in full, so the
  // operator chooses the qty up to what's available (320 pc picked from WIP);
  // defaults to the full lot.
  static const _available = 320; // pc available to dispatch
  int _dispatchQty = 320;

  void _stepQty(int d) =>
      setState(() => _dispatchQty = (_dispatchQty + d).clamp(0, _available));
  bool get _qtyValid => _dispatchQty > 0 && _dispatchQty <= _available;

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
    if (_submitting || !_qtyValid) return;
    setState(() => _submitting = true);
    // client_ref is auto-added by Data.submit (idempotency key).
    final res = await Data.submit(
      ref,
      '/dispatches',
      {
        'customer_id': 1,
        'vehicle_no': _veh,
        // Dispatch exactly the chosen quantity (a partial ship is normal).
        'lines': <Map<String, dynamic>>[
          {'material': 'Front fork 4521', 'qty': '$_dispatchQty'},
        ],
      },
      label: '${S.t('Dispatch', 'डिस्पॅच')} $_do · $_dispatchQty pc',
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
    Ui2Flow.set('dispatch.qty', _dispatchQty);
    nav.replace(ScreenId.gatePass);
  }

  // ---------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- shared header chip (DO code) ----

  Widget _doChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Y2.lineSoft,
          border: Border.all(color: const Color(0xFFD2DAE6)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(_do, style: F.mono(12, color: Y2.accent)),
      );

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + DO chip + customer
        ScreenHeader2(
          title: _customer.toUpperCase(),
          onBack: nav.pop,
          chip: _doChip(),
        ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _partsHeader(),
                const SizedBox(height: 11),
                _partRow(),
                const SizedBox(height: 11),
                _qtyCard(),
                const SizedBox(height: 11),
                _vehicleRow(),
                const SizedBox(height: 11),
                _infoBox(),
              ],
            ),
          ),
        ),
        // Footer action
        _footer(),
      ],
    );
  }

  // ---- desktop layout ----

  Widget _desktop() {
    return Column(
      children: [
        // No StatusBar2 on desktop — start with the screen header.
        ScreenHeader2(
          title: _customer.toUpperCase(),
          onBack: nav.pop,
          chip: _doChip(),
        ),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 760,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _partsHeader(),
                  const SizedBox(height: 12),
                  // Summary (parts to load) and the dispatch controls side by
                  // side: the loaded part on the left, qty + vehicle on the right.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _partRow(),
                            const SizedBox(height: 12),
                            _vehicleRow(),
                            const SizedBox(height: 12),
                            _infoBox(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _qtyCard(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _footer(wide: true),
      ],
    );
  }

  // ---- shared body sections ----

  Widget _partsHeader() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(S.t('PARTS TO LOAD', 'लोड करायचे भाग'),
              style: F.hind(11, w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
          Text(S.t('1 part', '1 भाग'), style: F.hind(11, color: Y2.muted)),
        ],
      );

  Widget _partRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
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
                Text('$_available', style: F.mono(17, color: Y2.ink)),
                const SizedBox(width: 3),
                Text(S.t('pc avail.', 'pc उपलब्ध'),
                    style: F.hind(11, color: Y2.muted)),
              ],
            ),
          ],
        ),
      );

  // Quantity to dispatch — editable, capped at what's available, so the operator
  // can ship a partial lot rather than always the whole.
  Widget _qtyCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rCard),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text(
                  S.t('QUANTITY TO DISPATCH · PC',
                      'डिस्पॅच करायचे प्रमाण · PC'),
                  style:
                      F.hind(11, w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
            ),
            Row(
              children: [
                _stepBtn(Icons.remove,
                    accent: false, onTap: () => _stepQty(-10)),
                const SizedBox(width: 12),
                Expanded(
                  child: QtyField2(
                    value: _dispatchQty,
                    max: _available,
                    onChanged: (v) =>
                        setState(() => _dispatchQty = v.toInt()),
                    fontSize: 46,
                  ),
                ),
                const SizedBox(width: 12),
                _stepBtn(Icons.add, accent: true, onTap: () => _stepQty(10)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  S.t('of $_available pc available', '$_available pc पैकी'),
                  style: F.hind(11, color: Y2.muted)),
            ),
            if (_dispatchQty <= 0)
              FieldHint(S.t(
                  'Enter a quantity to dispatch', 'डिस्पॅच करायचे प्रमाण भरा')),
          ],
        ),
      );

  // Vehicle row — tappable picker (reads as a select)
  Widget _vehicleRow() => Pressable2(
        onTap: _pickVehicle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
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
                        style:
                            F.hind(11, w: FontWeight.w400, color: Y2.muted)),
                    Text('$_veh · ${_vehTypeLabel(_vehType)}',
                        style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  ],
                ),
              ),
              const Icon(I2.chevronDown, size: 20, color: Y2.muted),
            ],
          ),
        ),
      );

  // Dashed info box
  Widget _infoBox() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  style: F.hind(12, w: FontWeight.w700, color: Y2.body)),
              TextSpan(
                  text: S.t(
                      ', posts the delivery to SAP, and reduces stock. Works offline — queues if no signal.',
                      ' तयार होतो, डिलिव्हरी SAP मध्ये पोस्ट होते आणि स्टॉक कमी होतो. ऑफलाइन चालते — सिग्नल नसल्यास रांगेत ठेवते.')),
            ],
          ),
        ),
      );

  // Footer action — shared between phone and desktop. The desktop branch caps the
  // button width so it lines up with the centered body; the phone branch is the
  // original full-bleed button (pass `wide: false`).
  Widget _footer({bool wide = false}) {
    final button = PrimaryButton2(
      label: _submitting
          ? S.t('Generating…', 'तयार करत आहे…')
          : S.t('Dispatch $_dispatchQty pc · gate pass',
              '$_dispatchQty pc डिस्पॅच · गेट पास'),
      busy: _submitting,
      enabled: _qtyValid,
      onTap: _confirm,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FB),
        border: Border(top: BorderSide(color: Y2.line)),
      ),
      child: wide ? ResponsiveContent(maxWidth: 760, child: button) : button,
    );
  }

  Widget _stepBtn(IconData icon,
          {required bool accent, required VoidCallback onTap}) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent ? const Color(0x121D4ED8) : null,
            border:
                Border.all(color: accent ? Y2.accent : const Color(0xFFD2DAE6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: accent ? Y2.accent : Y2.ink),
        ),
      );
}
