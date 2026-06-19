import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Confirm output — synced/posted success — prototype screen [04].
/// Centered confirmation; no back, no tab. Returns home or records another part.
class Ui2ConfirmSyncedScreen extends StatefulWidget {
  const Ui2ConfirmSyncedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ConfirmSyncedScreen> createState() => _Ui2ConfirmSyncedScreenState();
}

class _Ui2ConfirmSyncedScreenState extends State<Ui2ConfirmSyncedScreen> {
  PhoneNav get nav => widget.nav;

  // Posting timestamp — captured the moment the success screen mounts so the
  // operator gets a real "posted at" receipt rather than a constant.
  late final DateTime _postedAt;

  @override
  void initState() {
    super.initState();
    _postedAt = DateTime.now();
    // The payoff screen of the core task — reward it with a light haptic.
    HapticFeedback.lightImpact();
  }

  String get _time {
    final h = _postedAt.hour.toString().padLeft(2, '0');
    final m = _postedAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final docRaw = Ui2Flow.raw('confirm.doc');
    final done = Ui2Flow.get<int>('confirm.done');
    final plan = Ui2Flow.get<int>('confirm.plan');
    final good = Ui2Flow.get<int>('confirm.good');
    final reject = Ui2Flow.get<int>('confirm.reject');

    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Success ring + check — scale/fade in on mount (~400ms).
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    builder: (context, t, child) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.scale(scale: t, child: child),
                    ),
                    child: Container(
                      width: 74,
                      height: 74,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Y2.green, width: 3),
                      ),
                      child: const Icon(I2.check, size: 42, color: Y2.green),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Server status pill — reflects what the POST returned.
                Center(
                  child: Builder(builder: (_) {
                    final st = Ui2Flow.get<String>('confirm.serverStatus');
                    final pending = st != null &&
                        (st.contains('pend') ||
                            st.contains('queue') ||
                            st.contains('waiver') ||
                            st.contains('hold'));
                    return Pill2(
                      text: st == null
                          ? S.t('SYNCED', 'सिंक झाले')
                          : st.toUpperCase(),
                      fg: pending ? Y2.orange : Y2.green,
                      bg: pending ? Y2.orangeTint : Y2.greenTint,
                      borderColor: pending ? Y2.orangeLine : Y2.greenLine,
                    );
                  }),
                ),
                const SizedBox(height: 14),
                Text(
                  S.t('OUTPUT RECORDED', 'आउटपुट नोंदवले'),
                  textAlign: TextAlign.center,
                  style: F.khand(22, ls: 0.4, color: Y2.ink),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: F.hind(13, color: Y2.body, height: 1.5),
                    children: [
                      TextSpan(text: S.t('Doc ', 'दस्तावेज ')),
                      if (docRaw != null)
                        TextSpan(
                            text: 'PC-$docRaw',
                            style: F.mono(13, color: Y2.ink))
                      else
                        TextSpan(
                            text: S.t('number pending', 'क्रमांक प्रलंबित'),
                            style: F.hind(13, color: Y2.muted)),
                      TextSpan(text: S.t(' posted to SAP.', ' SAP ला पोस्ट झाले.')),
                      if (done != null && plan != null) ...[
                        const TextSpan(text: '\n'),
                        TextSpan(text: S.t('Now at ', 'आता ')),
                        TextSpan(
                            text: '$done/$plan',
                            style: F.mono(13, color: Y2.ink)),
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                // Posted-at timestamp + committed good/reject breakdown receipt.
                Text.rich(
                  TextSpan(
                    style: F.hind(11, color: Y2.muted),
                    children: [
                      TextSpan(text: S.t('Posted ', 'पोस्ट ')),
                      TextSpan(text: _time, style: F.mono(11, color: Y2.body)),
                      TextSpan(text: S.t(' · just now', ' · आत्ताच')),
                      if (good != null) ...[
                        const TextSpan(text: '   '),
                        TextSpan(
                            text: '$good',
                            style: F.mono(11, color: Y2.green)),
                        TextSpan(text: S.t(' good', ' चांगले')),
                        if ((reject ?? 0) > 0) ...[
                          TextSpan(text: '  ·  '),
                          TextSpan(
                              text: '$reject',
                              style: F.mono(11, color: Y2.red)),
                          TextSpan(text: S.t(' reject', ' नापास')),
                        ],
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                PrimaryButton2(
                  label: S.t('Back to home', 'मुख्य पानावर परत'),
                  onTap: () => nav.home(),
                ),
                const SizedBox(height: 10),
                OutlineButton2(
                  label: S.t('Record another part', 'दुसरा भाग नोंदवा'),
                  onTap: () => nav.replace(ScreenId.confirmForm),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
