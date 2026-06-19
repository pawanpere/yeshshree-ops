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
import '../widgets/polish2.dart';

/// Confirm — syncing — prototype screen [03]. Performs the REAL
/// POST /confirmations (through the retry queue) while showing the spinner,
/// then routes to synced / queued / back-to-form-on-error.
class Ui2ConfirmSyncingScreen extends ConsumerStatefulWidget {
  const Ui2ConfirmSyncingScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2ConfirmSyncingScreen> createState() =>
      _Ui2ConfirmSyncingScreenState();
}

class _Ui2ConfirmSyncingScreenState
    extends ConsumerState<Ui2ConfirmSyncingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  String? _error;
  bool _slow = false; // flips to a reassurance message after ~3s of posting

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
    // After a few seconds of waiting, reassure the operator it's safe to wait.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _error == null) setState(() => _slow = true);
    });
    _post();
  }

  Future<void> _post() async {
    setState(() {
      _error = null;
      _slow = false;
    });
    if (!_spin.isAnimating) _spin.repeat();
    final body = Ui2Flow.get<Map<String, dynamic>>('confirm.body');
    if (body == null) {
      // Defensive: nothing staged — just show the success screen.
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) nav.replace(ScreenId.confirmSynced);
      return;
    }
    final pending = Data.submit(
      ref,
      '/confirmations',
      body,
      label: '${S.t('Confirmation', 'नोंद')} ${Ui2Flow.get<int>('confirm.good')} ${S.t('pcs', 'नग')}',
    );
    await Future.delayed(const Duration(milliseconds: 650)); // min spinner time
    final res = await pending;
    if (!mounted) return;
    switch (res.status) {
      case WriteStatus.ok:
        Ui2Flow.set('confirm.doc',
            res.data?['id'] ?? res.data?['order_id']);
        Ui2Flow.set('confirm.serverStatus', res.data?['status']);
        nav.replace(ScreenId.confirmSynced);
      case WriteStatus.queued:
        nav.replace(ScreenId.confirmQueued);
      case WriteStatus.error:
        _spin.stop();
        HapticFeedback.heavyImpact();
        setState(() => _error = res.error?.message ??
            S.t('Could not post', 'नोंद करता आली नाही'));
    }
  }

  /// Human-readable summary of the staged payload, echoed under the spinner.
  String get _payloadSummary {
    final good = Ui2Flow.get<int>('confirm.good');
    final reject = Ui2Flow.get<int>('confirm.reject');
    final parts = <String>[S.t('FRONT FORK', 'फ्रंट फोर्क')];
    if (good != null) parts.add('$good ${S.t('good', 'चांगले')}');
    if (reject != null) parts.add('$reject ${S.t('reject', 'नापास')}');
    parts.add('${S.t('Shift', 'पाळी')} B');
    return parts.join(' · ');
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: _error == null ? _syncing() : _errorView(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _syncing() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: RotationTransition(
              turns: _spin,
              child: CustomPaint(painter: _SpinnerPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Text(S.t('SENDING TO SAP…', 'SAP ला पाठवत आहे…'),
                textAlign: TextAlign.center,
                style: F.khand(20, ls: 0.4, color: Y2.ink)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                S.t('Posting production confirmation',
                    'उत्पादन पुष्टी नोंदवत आहे'),
                textAlign: TextAlign.center,
                style: F.hind(13, color: Y2.muted)),
          ),
          // Echo of what's being sent, so the wait has context.
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_payloadSummary,
                textAlign: TextAlign.center,
                style: F.mono(11, color: Y2.body)),
          ),
          if (_slow)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  S.t('Still working — this is safe to wait',
                      'अजून सुरू आहे — थांबणे सुरक्षित आहे'),
                  textAlign: TextAlign.center,
                  style: F.hind(11, color: Y2.muted2)),
            ),
        ],
      );

  Widget _errorView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Y2.red, width: 3),
              ),
              child: const Icon(I2.error, size: 36, color: Y2.red),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(S.t("Couldn't post", 'नोंद झाली नाही'),
                textAlign: TextAlign.center,
                style: F.khand(20, ls: 0.4, color: Y2.ink)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: F.hind(13, color: Y2.muted)),
          ),
          const SizedBox(height: 22),
          // Retry is the most likely intent on a transient network error.
          PrimaryButton2(
            label: S.t('Retry', 'पुन्हा प्रयत्न'),
            onTap: _post,
          ),
          const SizedBox(height: 10),
          // Escape hatch — hold it on the phone and let the queue drain later.
          OutlineButton2(
            label: S.t('Save offline', 'ऑफलाइन जतन करा'),
            onTap: () => nav.replace(ScreenId.confirmQueued),
          ),
          const SizedBox(height: 12),
          Center(
            child: Pressable2(
              haptic: false,
              onTap: () => nav.replace(ScreenId.confirmForm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(S.t('Back to form', 'फॉर्मवर परत'),
                    style: F.hind(13, w: FontWeight.w600, color: Y2.muted)),
              ),
            ),
          ),
        ],
      );
}

class _SpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Y2.line;
    canvas.drawCircle(center, radius, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Y2.accent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -1.5708,
        1.5708, false, arc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
