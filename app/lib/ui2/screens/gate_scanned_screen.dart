import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Gate entry — scan read-back. Prototype screen [13]. Shows the values lifted
/// from a scanned challan for the operator to check (and correct inline) before
/// matching to an order. Confirming advances to the order-match screen.
class Ui2GateScannedScreen extends StatefulWidget {
  const Ui2GateScannedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateScannedScreen> createState() => _Ui2GateScannedScreenState();
}

class _Ui2GateScannedScreenState extends State<Ui2GateScannedScreen> {
  late final TextEditingController _vehicle =
      TextEditingController(text: 'MH12 AB 4421');
  late final TextEditingController _supplier =
      TextEditingController(text: 'Sandhar Steel');
  late final TextEditingController _challan =
      TextEditingController(text: 'CH-8841');
  late final TextEditingController _material =
      TextEditingController(text: 'CR coil 2.5mm');

  PhoneNav get nav => widget.nav;

  @override
  void dispose() {
    _vehicle.dispose();
    _supplier.dispose();
    _challan.dispose();
    _material.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron + title + SCANNED status.
        ScreenHeader2(
          title: S.t('GATE ENTRY', 'गेट एंट्री'),
          onBack: nav.pop,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Y2.green, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(S.t('SCANNED', 'स्कॅन झाले'),
                  style:
                      F.hind(10, w: FontWeight.w600, ls: 0.3, color: Y2.green)),
            ],
          ),
        ),
        // Body.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Read-from-scan banner.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0x0F1D4ED8), // rgba(29,78,216,.06)
                    border: Border.all(color: const Color(0xFFBCD0F5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    S.t('READ FROM SCAN — CHECK & CONFIRM',
                        'स्कॅनमधून वाचले — तपासा आणि पुष्टी करा'),
                    style: F.hind(10, w: FontWeight.w600, ls: 0.5, color: Y2.accent),
                  ),
                ),
                const SizedBox(height: 10),
                _field(S.t('Vehicle', 'वाहन'),
                    _editable(_vehicle, F.mono(16, color: Y2.ink))),
                const SizedBox(height: 10),
                _field(
                    S.t('Supplier', 'पुरवठादार'),
                    _editable(_supplier,
                        F.hind(16, w: FontWeight.w600, color: Y2.ink))),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _field(S.t('Challan', 'चलन'),
                          _editable(_challan, F.mono(15, color: Y2.ink))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                          S.t('Material', 'मटेरियल'),
                          _editable(_material,
                              F.hind(14, w: FontWeight.w600, color: Y2.ink))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Footer: match to an order.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: PrimaryButton2(
            label: S.t('Match to an order', 'ऑर्डरशी जुळवा'),
            onTap: () => nav.replace(ScreenId.gateMatch),
          ),
        ),
      ],
    );
  }

  /// In-place editable value, styled like the prototype's static read-back text,
  /// with an accent focus underline so the "check & correct" intent is afforded.
  Widget _editable(TextEditingController controller, TextStyle style) =>
      TextField(
        controller: controller,
        style: style,
        cursorColor: Y2.accent,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.only(bottom: 2),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Y2.line, width: 1),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Y2.accent, width: 1.5),
          ),
        ),
      );

  /// White hairline card: small muted label over a value, with a trailing
  /// pencil cue so the operator knows the scanned value is correctable inline.
  Widget _field(String label, Widget value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: value),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Icon(I2.edit, size: 14, color: Y2.muted),
                ),
              ],
            ),
          ],
        ),
      );
}
