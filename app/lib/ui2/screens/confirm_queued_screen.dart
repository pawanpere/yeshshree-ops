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

/// Confirm — queued offline result — prototype screen [05]. No network: the
/// production confirmation is saved on the phone and will post when back online.
/// Shows the real queued reference (from [Ui2Flow]) when the form stashed one,
/// falling back to the prototype literal.
class Ui2ConfirmQueuedScreen extends StatefulWidget {
  const Ui2ConfirmQueuedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ConfirmQueuedScreen> createState() => _Ui2ConfirmQueuedScreenState();
}

class _Ui2ConfirmQueuedScreenState extends State<Ui2ConfirmQueuedScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    // Soft confirmation that the write is safely held — matches the synced
    // screen's entrance haptic so the three result states share a language.
    HapticFeedback.lightImpact();
  }

  /// The queued reference shown in the body. Prefers an explicit queuedId/doc,
  /// then the short head of the stashed client_ref, else the prototype literal.
  String get _queuedRef {
    final qid = Ui2Flow.raw('confirm.queuedId') ?? Ui2Flow.raw('confirm.doc');
    if (qid != null) return qid.toString();
    final body = Ui2Flow.get<Map<String, dynamic>>('confirm.body');
    final ref = body?['client_ref']?.toString();
    if (ref != null && ref.isNotEmpty) {
      return 'CNF ${ref.substring(0, ref.length >= 4 ? 4 : ref.length).toUpperCase()}';
    }
    return 'CNF 4521';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sync-pending ring marker — scale/fade in on mount, shared
                  // motion language with the synced/error result screens.
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
                          border: Border.all(color: Y2.orange, width: 3),
                        ),
                        child:
                            const Icon(I2.syncPending, size: 38, color: Y2.orange),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // OFFLINE status pill — encodes the queued state at a glance.
                  Center(
                    child: Pill2(
                      text: S.t('OFFLINE', 'ऑफलाइन'),
                      fg: Y2.orange,
                      bg: Y2.orangeTint,
                      borderColor: Y2.orangeLine,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    S.t('SAVED ON THIS PHONE', 'या फोनवर जतन केले'),
                    textAlign: TextAlign.center,
                    style: F.khand(22, ls: 0.4, color: Y2.ink),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: F.hind(13, color: Y2.body, height: 1.5),
                      children: [
                        TextSpan(
                            text: S.t('No network now. ', 'सध्या नेटवर्क नाही. ')),
                        TextSpan(
                            text: _queuedRef,
                            style: F.mono(13, color: Y2.ink)),
                        TextSpan(
                            text: S.t(
                                ' is queued and will post automatically when you’re back online. Nothing lost.',
                                ' रांगेत आहे आणि तुम्ही पुन्हा ऑनलाइन आल्यावर आपोआप पोस्ट होईल. काहीही हरवले नाही.')),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  // Queue context — reassures it will retry on its own.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Glyph(GlyphShape.dot, Y2.orange, size: 7),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          S.t('Will retry automatically',
                              'आपोआप पुन्हा प्रयत्न होईल'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: F.hind(11, color: Y2.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  PrimaryButton2(
                    label: S.t('Open sync queue', 'सिंक रांग उघडा'),
                    onTap: () => nav.home(),
                  ),
                  const SizedBox(height: 10),
                  OutlineButton2(
                    label: S.t('Back to home', 'मुख्य पानावर परत'),
                    onTap: nav.home,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
