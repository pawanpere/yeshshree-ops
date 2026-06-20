import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Gate entry — offline quick-entry — prototype screen [35]. No-network branch:
/// free-text vehicle/driver/vendor captured into real fields, stashed into the
/// flow, and queued via Data.submit (failure ignored for the offline demo) —
/// then the saved confirmation screen.
class Ui2OfflineGateScreen extends ConsumerStatefulWidget {
  const Ui2OfflineGateScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2OfflineGateScreen> createState() =>
      _Ui2OfflineGateScreenState();
}

class _Ui2OfflineGateScreenState extends ConsumerState<Ui2OfflineGateScreen> {
  PhoneNav get nav => widget.nav;

  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  final _vendor = TextEditingController();

  late final String _gateTime; // real current time, captured at screen open.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _gateTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // Re-evaluate the CTA + inline errors on every keystroke in any field.
    for (final c in [_vehicle, _driver, _vendor]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _driver.dispose();
    _vendor.dispose();
    super.dispose();
  }

  // All three fields are required and must be valid: a strict Indian plate, and
  // a real (≥3-char, contains a letter) driver name and vendor — so "AB" no
  // longer enables Save. The plate is normalised (uppercased, spaces stripped).
  bool get _vehicleValid => V.plate(_vehicle.text);
  bool get _driverValid => V.name(_driver.text);
  bool get _vendorValid => V.freeText(_vendor.text);
  bool get _canSave => _vehicleValid && _driverValid && _vendorValid;

  Future<void> _save() async {
    if (_busy || !_canSave) return;
    final veh = V.normPlate(_vehicle.text);
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final vendor = _vendor.text.trim();
    // Carry values into the saved screen.
    Ui2Flow.set('offlineGate.vehicle', veh);
    Ui2Flow.set('offlineGate.vendor', vendor);
    Ui2Flow.set('offlineGate.gateTime', _gateTime);
    // Queue the gate-in. Offline / failure is expected here — ignore it; the
    // entry is captured locally and matched on sync.
    final res = await Data.submit(
      ref,
      '/gate-entries',
      <String, dynamic>{
        'doc_type': 'invoice',
        'vehicle_no': veh,
        'driver_name': _driver.text.trim(),
      },
      label: '${S.t('Gate entry', 'गेट नोंद')} $veh',
    );
    if (res.ok) Ui2Flow.set('gate.entryId', res.data?['id']);
    // Tell the saved screen the real outcome: posted live vs queued offline. The
    // manual-entry path is used online too, so the confirmation must not always
    // claim "queued / when you're back online".
    Ui2Flow.set('offlineGate.queued', res.queued);
    if (!mounted) return;
    nav.replace(ScreenId.offlineGateSaved);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _canSave;
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + title.
        ScreenHeader2(
          title: S.t('ADD GATE ENTRY', 'गेट नोंद जोडा'),
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Quick manual-entry notice (walk-in / no-scan arrival). Works
                // online or offline — the entry syncs automatically either way.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0x12C2410C), // rgba(194,65,12,0.07)
                    border: Border.all(color: const Color(0xFFF0B89A)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: const BoxDecoration(
                            color: Y2.orange, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                S.t('Quick gate entry',
                                    'झटपट गेट नोंद'),
                                style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                            Text(
                                S.t(
                                    'For a walk-in or no-scan arrival. Let the truck through now; type what you can and it matches to an order automatically.',
                                    'वॉक-इन किंवा स्कॅन नसलेल्या आवकसाठी. ट्रक आता आत येऊ द्या; जे शक्य आहे ते टाइप करा आणि ते आपोआप ऑर्डरशी जुळते.'),
                                style: F.hind(12, color: Y2.body, height: 1.35)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                // Vehicle number field (real TextField).
                _field(
                  S.t('Vehicle number', 'वाहन क्रमांक'),
                  Icons.local_shipping_outlined,
                  TextField(
                    controller: _vehicle,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: V.plateInput,
                    style: F.mono(18, color: Y2.ink),
                    cursorColor: Y2.accent,
                    decoration: _inputDeco('MH __ __ ____',
                        F.mono(18, color: Y2.muted)),
                  ),
                  // Show the format hint only once they've typed something invalid.
                  error: _vehicle.text.trim().isNotEmpty && !_vehicleValid
                      ? S.t('Enter a full plate, e.g. MH12 AB 4421',
                          'पूर्ण क्रमांक भरा, उदा. MH12 AB 4421')
                      : null,
                ),
                const SizedBox(height: 11),
                // Driver name field (real TextField).
                _field(
                  S.t('Driver name', 'चालकाचे नाव'),
                  Icons.person_outline_rounded,
                  TextField(
                    controller: _driver,
                    textCapitalization: TextCapitalization.words,
                    style: F.hind(15, color: Y2.ink),
                    cursorColor: Y2.accent,
                    decoration: _inputDeco(S.t('Type name…', 'नाव टाइप करा…'),
                        F.hind(15, color: Y2.muted)),
                  ),
                  error: _driver.text.trim().isNotEmpty && !_driverValid
                      ? S.t('Enter the driver’s name (min 3 letters)',
                          'चालकाचे नाव भरा (किमान ३ अक्षरे)')
                      : null,
                ),
                const SizedBox(height: 11),
                // Vendor field (real free-text TextField).
                _field(
                  S.t('Vendor (free text)', 'विक्रेता (मुक्त मजकूर)'),
                  Icons.store_outlined,
                  TextField(
                    controller: _vendor,
                    textCapitalization: TextCapitalization.words,
                    style: F.hind(15, color: Y2.ink),
                    cursorColor: Y2.accent,
                    decoration: _inputDeco(
                        S.t('e.g. Sandhar Steel', 'उदा. Sandhar Steel'),
                        F.hind(15, color: Y2.muted)),
                  ),
                  error: _vendor.text.trim().isNotEmpty && !_vendorValid
                      ? S.t('Enter the vendor name (min 3 letters)',
                          'विक्रेत्याचे नाव भरा (किमान ३ अक्षरे)')
                      : null,
                ),
                const SizedBox(height: 11),
                // Gate time row — real current time.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FB),
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(S.t('Gate time (now)', 'गेट वेळ (आता)'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: F.hind(13, color: Y2.body)),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Y2.lineSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(S.t('auto', 'स्वयं'),
                                style: F.hind(9,
                                    w: FontWeight.w600,
                                    ls: 0.3,
                                    color: Y2.muted)),
                          ),
                          const SizedBox(width: 7),
                          Text(_gateTime,
                              style: F.mono(13,
                                  w: FontWeight.w700, color: Y2.ink)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Footer CTA.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: S.t('Let in & save', 'आत घ्या आणि जतन करा'),
            busy: _busy,
            enabled: canSave,
            onTap: _save,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String hint, TextStyle hintStyle) =>
      InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 3),
        hintText: hint,
        hintStyle: hintStyle,
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Y2.line, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Y2.accent, width: 1.5),
        ),
      );

  Widget _field(String label, IconData icon, Widget value, {String? error}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          // Red hairline when the field is filled-but-invalid, for a clear signal.
          border: Border.all(color: error != null ? Y2.red : Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: Y2.muted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
                  const SizedBox(height: 2),
                  value,
                  if (error != null) FieldHint(error),
                ],
              ),
            ),
          ],
        ),
      );
}
