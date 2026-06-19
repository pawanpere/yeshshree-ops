import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';
import '../widgets/qty_field2.dart';

/// Issue material — over-limit state — prototype screen [07]. Same form chrome
/// as the issue screen, but the quantity exceeds today's allowed limit, so the
/// warning banner appears and the primary action becomes "request the extra".
/// The qty stepper recomputes the over-limit delta; a reason picker tags the
/// override request; requesting advances to the waiting screen.
class Ui2IssueOverlimitScreen extends StatefulWidget {
  const Ui2IssueOverlimitScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2IssueOverlimitScreen> createState() =>
      _Ui2IssueOverlimitScreenState();
}

class _Ui2IssueOverlimitScreenState extends State<Ui2IssueOverlimitScreen> {
  static const _f6 = Color(0xFFF6F8FB);
  static const _bChev = Color(0xFFD2DAE6);
  static const _bBanner = Color(0xFFF0B89A);
  static const _limit = 500; // allowed today, kg

  PhoneNav get nav => widget.nav;

  int _qty = 560;
  int? _reasonId;
  String? _reasonLabel; // null until the operator picks an override reason

  int get _over => (_qty - _limit).clamp(0, 99999);

  void _step(int d) => setState(() => _qty = (_qty + d).clamp(0, 99999));

  Future<void> _pickReason() async {
    nav.overlay(const _PickerLoading2());
    final res = await Data.reasonCodes(kind: 'reject');
    if (!mounted) return;
    final options = [
      for (final r in res.data)
        Picker2Option<int?>(
          S.t('${r['label_en'] ?? r['code']}',
              '${r['label_mr'] ?? r['label_en'] ?? r['code']}'),
          (r['id'] as num?)?.toInt(),
          sub: r['code'] as String?,
        ),
    ];
    nav.overlay(Picker2Sheet<int?>(
      title: S.t('Reason', 'कारण'),
      options: options,
      onPick: (id) {
        final picked = options.firstWhere((o) => o.value == id,
            orElse: () => options.isNotEmpty
                ? options.first
                : Picker2Option<int?>(
                    S.t('Urgent rework order', 'तातडीचे रिवर्क ऑर्डर'), null));
        setState(() {
          _reasonId = id;
          _reasonLabel = picked.label;
        });
        nav.hideOverlay();
      },
    ));
  }

  void _ask() {
    if (_reasonLabel == null) return; // reason is required for an override
    // Stash the pending request for the waiting / approved / done screens.
    Ui2Flow.set('issue.material', S.t('CR coil 2.5mm', 'CR कॉइल 2.5mm'));
    Ui2Flow.set('issue.qty', _qty);
    Ui2Flow.set('issue.over', _over);
    Ui2Flow.set('issue.reason', _reasonLabel);
    if (_reasonId != null) Ui2Flow.set('issue.reasonId', _reasonId);
    nav.replace(ScreenId.issueWaiting);
  }

  void _issueLimit() {
    // Clamp to the allowed limit and proceed with a normal in-limit issue.
    Ui2Flow.set('issue.material', S.t('CR coil 2.5mm', 'CR कॉइल 2.5mm'));
    Ui2Flow.set('issue.qty', _limit);
    Ui2Flow.set('issue.dest', S.t('Line A · Press 3', 'लाइन A · प्रेस 3'));
    nav.replace(ScreenId.issueDone);
  }

  @override
  Widget build(BuildContext context) {
    final reasonChosen = _reasonLabel != null;
    return Column(
      children: [
        const StatusBar2(),
        // ---- Header: shared back affordance + title + mode pill ----
        ScreenHeader2(
          title: S.t('ISSUE MATERIAL', 'माल जारी करा'),
          onBack: nav.pop,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Y2.orangeTint,
              border: Border.all(color: Y2.orangeLine),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(S.t('OVER PLAN', 'जास्त'),
                style: F.hind(10,
                    w: FontWeight.w600, ls: 0.5, color: Y2.orange)),
          ),
        ),
        // ---- Scrollable body ----
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Material
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('Material', 'माल'),
                          style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Y2.lineSoft,
                              border: Border.all(color: _bChev),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child:
                                Text('CR-25', style: F.mono(12, color: Y2.accent)),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(S.t('CR coil 2.5mm', 'CR कॉइल 2.5mm'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: F.hind(15,
                                    w: FontWeight.w600, color: Y2.ink)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Issue to
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.t('Issue to', 'जारी करा'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: F.hind(11,
                                    w: FontWeight.w400, color: Y2.muted)),
                            const SizedBox(height: 2),
                            Text(S.t('Line A · Press 3', 'लाइन A · प्रेस 3'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: F.hind(15,
                                    w: FontWeight.w600, color: Y2.ink)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(I2.chevronDown, size: 20, color: Y2.muted),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Stock tiles
                Row(
                  children: [
                    Expanded(
                        child: _miniStat(S.t('In stock', 'स्टॉकमध्ये'), '2,400')),
                    const SizedBox(width: 11),
                    Expanded(
                        child:
                            _miniStat(S.t('Allowed today', 'आज परवानगी'), '$_limit')),
                  ],
                ),
                const SizedBox(height: 12),
                // Quantity stepper (over limit → orange value)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 15, vertical: 13),
                  decoration: BoxDecoration(
                    color: Y2.card,
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(Y2.rCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('QUANTITY TO ISSUE · KG', 'जारी प्रमाण · KG'),
                          style: F.hind(11,
                              w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _stepBtn(Icons.remove, false, () => _step(-10)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: QtyField2(
                              value: _qty,
                              onChanged: (v) =>
                                  setState(() => _qty = v.toInt()),
                              color: _qty > _limit ? Y2.orange : Y2.ink,
                              fontSize: 46,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _stepBtn(Icons.add, true, () => _step(10)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ---- Over-limit warning banner ----
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: const Color(0x14C2410C), // rgba(194,65,12,0.08)
                    border: Border.all(color: _bBanner),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(I2.warning,
                                size: 18, color: Y2.orange),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    S.t("$_over kg over today's limit",
                                        'आजच्या मर्यादेपेक्षा $_over kg जास्त'),
                                    style: F.hind(15,
                                        w: FontWeight.w600, color: Y2.ink)),
                                const SizedBox(height: 2),
                                Text(
                                    S.t(
                                        'Limit is $_limit kg. Ask the supervisor to allow the extra — your request is logged against the issue.',
                                        'मर्यादा $_limit kg आहे. जास्तीसाठी सुपरवायझरला विचारा — तुमची विनंती इश्यूसोबत नोंदली जाते.'),
                                    style: F.hind(12, color: Y2.body)),
                                const SizedBox(height: 4),
                                Text(
                                    S.t(
                                        'Parallel-run mode · stock is not blocked, but the request is recorded.',
                                        'पॅरलल-रन मोड · स्टॉक थांबवला जात नाही, पण विनंती नोंदली जाते.'),
                                    style: F.hind(11,
                                        w: FontWeight.w600, color: Y2.orange)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Reason row (tappable → reason picker), required
                      Pressable2(
                        onTap: _pickReason,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 11),
                          decoration: BoxDecoration(
                            color: Y2.card,
                            border: Border.all(
                                color: reasonChosen ? Y2.line : _bBanner),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(S.t('Reason', 'कारण'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: F.hind(11,
                                            w: FontWeight.w400,
                                            color: Y2.muted)),
                                    const SizedBox(height: 1),
                                    Text(
                                        reasonChosen
                                            ? _reasonLabel!
                                            : S.t('Choose a reason',
                                                'कारण निवडा'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        style: F.hind(13,
                                            w: FontWeight.w600,
                                            color: reasonChosen
                                                ? Y2.ink
                                                : Y2.muted)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(I2.chevronDown,
                                  size: 20, color: Y2.muted),
                            ],
                          ),
                        ),
                      ),
                      if (!reasonChosen) ...[
                        const SizedBox(height: 6),
                        Text(
                            S.t('Reason required for override',
                                'ओव्हरराइडसाठी कारण आवश्यक'),
                            style: F.hind(11,
                                w: FontWeight.w600, color: Y2.orange)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ---- Footer actions ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: _f6,
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton2(
                label: S.t('Ask supervisor for +$_over kg',
                    'सुपरवायझरला +$_over kg विचारा'),
                enabled: reasonChosen,
                onTap: _ask,
              ),
              const SizedBox(height: 9),
              OutlineButton2(
                label: S.t('Issue $_limit kg (the limit) instead',
                    'त्याऐवजी $_limit kg (मर्यादा) जारी करा'),
                onTap: _issueLimit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: _f6,
          border: Border.all(color: Y2.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.mono(17, color: Y2.navy)),
                ),
                Text(S.t(' kg', ' kg'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: F.hind(11, w: FontWeight.w400, color: Y2.muted)),
              ],
            ),
          ],
        ),
      );

  Widget _stepBtn(IconData icon, bool accent, VoidCallback onTap) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent ? const Color(0x121D4ED8) : null,
            border: Border.all(color: accent ? Y2.accent : _bChev),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: accent ? Y2.accent : Y2.ink),
        ),
      );
}

/// Sheet shown while the reason-code read is still resolving.
class _PickerLoading2 extends StatelessWidget {
  const _PickerLoading2();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Y2.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(S.t('Loading…', 'लोड होत आहे…'),
              textAlign: TextAlign.center,
              style: F.hind(12, color: Y2.muted)),
        ],
      ),
    );
  }
}
