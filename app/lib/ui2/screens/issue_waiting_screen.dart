import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Store — issue over-limit "REQUEST SENT" waiting state (prototype screen [08]).
/// Auto-advances to the approved screen after the supervisor "responds".
class Ui2IssueWaitingScreen extends StatefulWidget {
  const Ui2IssueWaitingScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2IssueWaitingScreen> createState() => _Ui2IssueWaitingScreenState();
}

class _Ui2IssueWaitingScreenState extends State<Ui2IssueWaitingScreen> {
  Timer? _timer;
  Timer? _tick;
  int _elapsed = 0; // seconds since the request was sent

  PhoneNav get nav => widget.nav;

  String get _material =>
      Ui2Flow.get<String>('issue.material') ??
      S.t('CR coil 2.5mm', 'CR coil 2.5mm');
  int get _qty => Ui2Flow.get<int>('issue.qty') ?? 850;
  int get _over => Ui2Flow.get<int>('issue.over') ?? 50;
  String? get _reason => Ui2Flow.get<String>('issue.reason');

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) nav.replace(ScreenId.issueApproved);
    });
    // Ticking "sent Ns ago" so the pending state reads as live, not frozen.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Semantics(
                  label: S.t('Waiting for supervisor approval',
                      'सुपरवायझरच्या मंजुरीची प्रतीक्षा'),
                  child: const Center(
                    child: SizedBox(
                      width: 66,
                      height: 66,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Y2.orange,
                        backgroundColor: Y2.line,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  S.t('REQUEST SENT', 'विनंती पाठवली'),
                  textAlign: TextAlign.center,
                  style: F.khand(21, ls: 0.4, color: Y2.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t('Sent ${_elapsed}s ago', '${_elapsed}से पूर्वी पाठवली'),
                  textAlign: TextAlign.center,
                  style: F.hind(11, w: FontWeight.w600, color: Y2.orange),
                ),
                const SizedBox(height: 8),
                _subtitle(),
                const SizedBox(height: 20),
                // Self-describing request summary.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FB),
                    border: Border.all(color: Y2.line),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    children: [
                      _sumRow(_material, '$_qty kg'),
                      if (_reason != null) ...[
                        const SizedBox(height: 7),
                        _sumRow(S.t('Reason', 'कारण'), _reason!, mono: false),
                      ],
                      const SizedBox(height: 7),
                      _sumRow(S.t('Over limit', 'मर्यादेपेक्षा'), '+$_over kg'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlineButton2(
                  label: S.t('Cancel request', 'विनंती रद्द करा'),
                  onTap: nav.home,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sumRow(String left, String right, {bool mono = true}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: Text(left, style: F.hind(13, color: Y2.body))),
          const SizedBox(width: 10),
          Text(right,
              style: mono
                  ? F.mono(13, color: Y2.ink)
                  : F.hind(13, w: FontWeight.w600, color: Y2.ink)),
        ],
      );

  Widget _subtitle() => Text.rich(
        TextSpan(
          style: F.hind(13, color: Y2.body, height: 1.5),
          children: [
            TextSpan(text: S.t('Waiting for ', 'प्रतीक्षेत — ')),
            TextSpan(
              text: S.t('Ramesh (supervisor)', 'रमेश (पर्यवेक्षक)'),
              style: F.hind(13, w: FontWeight.w700, color: Y2.ink, height: 1.5),
            ),
            TextSpan(
              text: S.t(
                ' to allow the extra $_over kg. You can keep working — this waits in the background.',
                ' यांनी अतिरिक्त $_over kg ला परवानगी द्यावी. तुम्ही काम सुरू ठेवू शकता — हे पार्श्वभूमीत प्रतीक्षेत राहते.',
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      );
}
