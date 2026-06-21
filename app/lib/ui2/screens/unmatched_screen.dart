import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Unmatched vehicle — prototype screen [28]. Gate arrival with no SAP
/// pre-advice: confirm/edit the plate, optionally attach a PO from a manual
/// search, then log it and let the office match it later.
class Ui2UnmatchedScreen extends StatefulWidget {
  const Ui2UnmatchedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2UnmatchedScreen> createState() => _Ui2UnmatchedScreenState();
}

class _Ui2UnmatchedScreenState extends State<Ui2UnmatchedScreen> {
  PhoneNav get nav => widget.nav;

  final _vehicle = TextEditingController(text: 'MH09 KL 2210');

  String? _poLabel; // chosen PO display, null until a PO is attached.
  String? _poNo;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the CTA + inline error on every keystroke in the plate field.
    _vehicle.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _vehicle.dispose();
    super.dispose();
  }

  // The plate must be a strict Indian plate before it can be logged; the seeded
  // 'MH09 KL 2210' already passes. Stored normalised (uppercased, spaces stripped).
  bool get _vehicleValid => V.plate(_vehicle.text);
  bool get _canLog => _vehicleValid;

  Future<void> _pickPo() async {
    final res = await Data.purchaseOrders();
    final options = [
      for (final p in res.data)
        Picker2Option<String?>(
          S.t('${p['sap_po_no'] ?? p['vendor']}', '${p['sap_po_no'] ?? p['vendor']}'),
          p['sap_po_no'] as String?,
          sub: '${p['vendor'] ?? ''} · ${p['material'] ?? ''}',
        ),
    ];
    nav.overlay(Picker2Sheet<String?>(
      title: S.t('Search a PO', 'PO शोधा'),
      options: options,
      onPick: (po) {
        final picked = options.firstWhere((o) => o.value == po);
        setState(() {
          _poNo = po;
          _poLabel = picked.label;
        });
        nav.hideOverlay();
      },
    ));
  }

  void _clearPo() => setState(() {
        _poNo = null;
        _poLabel = null;
      });

  void _logIt() {
    if (!_canLog) return; // Re-guard: never log an invalid plate.
    // Stash for the gate flow; the office matches it later.
    Ui2Flow.set('offlineGate.vehicle', V.normPlate(_vehicle.text));
    if (_poNo != null) Ui2Flow.set('gate.po', _poNo);
    nav.home();
  }

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('UNMATCHED VEHICLE', 'जुळत नसलेले वाहन'),
          onBack: nav.pop,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _warningBanner(),
                const SizedBox(height: 11),
                // Vehicle plate — editable so the gate user can confirm/correct.
                _field(S.t('Vehicle', 'वाहन'), _vehicleInput()),
                const SizedBox(height: 11),
                // Search a PO manually → opens Picker2 of purchase orders.
                _poRow(),
              ],
            ),
          ),
        ),
        _phoneFooter(),
      ],
    );
  }

  Widget _phoneFooter() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrimaryButton2(
              label: S.t('Log as unmatched · send to office',
                  'जुळत नसलेले म्हणून नोंदवा · ऑफिसला पाठवा'),
              enabled: _canLog,
              onTap: _logIt,
            ),
            const SizedBox(height: 9),
            OutlineButton2(
              label: S.t('Back to arrivals', 'आवकीकडे परत'),
              onTap: nav.pop,
            ),
          ],
        ),
      );

  // ---- desktop layout ----

  Widget _desktop() {
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('UNMATCHED VEHICLE', 'जुळत नसलेले वाहन'),
          onBack: nav.pop,
        ),
        Expanded(
          child: ResponsiveContent(
            // A short two-field form: cap it tight so the inputs stay readable
            // and don't stretch edge-to-edge on a wide monitor.
            maxWidth: 760,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _warningBanner(),
                  const SizedBox(height: 14),
                  // Vehicle plate + PO search side by side; both wrap cleanly so
                  // neither column can overflow from 820px up.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child:
                            _field(S.t('Vehicle', 'वाहन'), _vehicleInput()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: _poRow()),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        _desktopFooter(),
      ],
    );
  }

  Widget _desktopFooter() => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: ResponsiveContent(
          // Match the form column above so the status line + buttons stay
          // aligned under the fields instead of running the full shell width.
          maxWidth: 760,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _canLog
                      ? S.t('Plate confirmed · ready to log',
                          'क्रमांक निश्चित · नोंदवण्यास तयार')
                      : S.t('Enter a valid plate to log',
                          'नोंदवण्यासाठी वैध क्रमांक भरा'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(12, color: Y2.muted),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: OutlineButton2(
                  label: S.t('Back to arrivals', 'आवकीकडे परत'),
                  onTap: nav.pop,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 280,
                child: PrimaryButton2(
                  label: S.t('Log as unmatched · send to office',
                      'जुळत नसलेले म्हणून नोंदवा · ऑफिसला पाठवा'),
                  enabled: _canLog,
                  onTap: _logIt,
                ),
              ),
            ],
          ),
        ),
      );

  // ---- shared pieces (identical content on both form factors) ----

  Widget _warningBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0x12C2410C), // rgba(194,65,12,0.07)
          border: Border.all(color: const Color(0xFFF0B89A)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Glyph(GlyphShape.triangle, Y2.orange, size: 12),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      S.t('No pre-advice for this challan',
                          'या चलनासाठी पूर्वसूचना नाही'),
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  Text(
                      S.t(
                          "Nothing in SAP matches CH-9120. Don't turn it away — log it and let the office match it.",
                          'SAP मध्ये CH-9120 शी काहीही जुळत नाही. परत पाठवू नका — नोंदवा आणि ऑफिसला जुळवू द्या.'),
                      style: F.hind(12, color: Y2.body)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _vehicleInput() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _vehicle,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: V.plateInput,
            style: F.mono(16, color: Y2.ink),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'MH __ __ ____',
              hintStyle: F.mono(16, color: Y2.muted),
            ),
          ),
          // Show the format hint only once a non-empty plate is invalid.
          FieldHint(
            S.t('Enter a full plate, e.g. MH12 AB 4421',
                'पूर्ण क्रमांक भरा, उदा. MH12 AB 4421'),
            show: _vehicle.text.trim().isNotEmpty && !_vehicleValid,
          ),
        ],
      );

  Widget _poRow() {
    final attached = _poLabel != null;
    return Pressable2(
      onTap: _pickPo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: attached ? Y2.greenTint : Y2.card,
          border: Border.all(color: attached ? Y2.greenLine : Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      attached
                          ? S.t('PO attached', 'PO जोडले')
                          : S.t('Search a PO manually', 'PO स्वतः शोधा'),
                      style: F.hind(11,
                          w: FontWeight.w400,
                          color: attached ? Y2.green : Y2.muted)),
                  Text(
                      _poLabel ??
                          S.t('Type PO / supplier…',
                              'PO / पुरवठादार टाइप करा…'),
                      style: F.hind(14,
                          w: FontWeight.w600,
                          color: attached ? Y2.green : Y2.ink)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (attached)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearPo,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(I2.close, size: 18, color: Y2.green),
                ),
              )
            else
              const Icon(I2.search, size: 18, color: Y2.muted),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, Widget value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 1),
            value,
          ],
        ),
      );
}
