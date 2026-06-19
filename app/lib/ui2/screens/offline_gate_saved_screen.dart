import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Gate — manual entry saved — prototype screen [36]. Confirms a manual gate-in.
/// Outcome-aware: if it posted live the screen reads "saved & syncing"; if it was
/// queued offline it reads "saved on this phone · will match when back online"
/// (driven by `offlineGate.queued`). No back, no tab.
class Ui2OfflineGateSavedScreen extends StatefulWidget {
  const Ui2OfflineGateSavedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2OfflineGateSavedScreen> createState() =>
      _Ui2OfflineGateSavedScreenState();
}

class _Ui2OfflineGateSavedScreenState extends State<Ui2OfflineGateSavedScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    // The plate the gate user just saved (fall back to the demo literal).
    final vehicle = Ui2Flow.get<String>('offlineGate.vehicle');
    final vehicleText =
        (vehicle != null && vehicle.isNotEmpty) ? vehicle : 'MH09 KL 2210';
    final gateTime = Ui2Flow.get<String>('offlineGate.gateTime') ?? '14:32';
    // Outcome of the write: queued offline vs posted live. Drives the framing so
    // the screen never falsely claims "queued / when you're back online" online.
    final queued = Ui2Flow.get<bool>('offlineGate.queued') ?? false;
    final accent = queued ? Y2.orange : Y2.green;
    final mark = queued ? I2.queued : I2.checkCircle;
    final headline = queued
        ? S.t('SAVED ON THIS PHONE', 'या फोनवर जतन केले')
        : S.t('GATE ENTRY SAVED', 'गेट नोंद जतन केली');
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Row(
            children: [
              Icon(mark, size: 18, color: accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(headline,
                    style: F.khand(17, ls: 0.3, color: accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  // queued ring marker
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutBack,
                      builder: (context, t, child) => Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.scale(
                            scale: 0.8 + 0.2 * t.clamp(0.0, 1.0), child: child),
                      ),
                      child: Container(
                        width: 74,
                        height: 74,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 3),
                        ),
                        child: Icon(mark, size: 34, color: accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: F.khand(22, ls: 0.4, color: Y2.ink),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: F.hind(13, color: Y2.body, height: 1.5),
                      children: [
                        TextSpan(text: S.t('Entry ', 'नोंद ')),
                        TextSpan(
                            text: vehicleText,
                            style: F.mono(13, color: Y2.ink)),
                        TextSpan(
                            text: S.t(
                                ' saved with gate time ', ' गेट वेळेसह जतन केली ')),
                        TextSpan(
                            text: gateTime,
                            style: F.hind(13,
                                w: FontWeight.w700, color: Y2.body)),
                        TextSpan(
                            text: queued
                                ? S.t(
                                    '. It’s saved on this phone and will match to an order when you’re back online.',
                                    '. ती या फोनवर जतन केली आहे आणि तुम्ही पुन्हा ऑनलाइन आल्यावर ऑर्डरशी जुळेल.')
                                : S.t(
                                    '. It’s saved and matching to an order now.',
                                    '. ती जतन केली आहे आणि आता ऑर्डरशी जुळत आहे.')),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Queued status line.
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: queued ? Y2.orangeTint : Y2.greenTint,
                        border: Border.all(
                            color: queued ? Y2.orangeLine : Y2.greenLine),
                        borderRadius: BorderRadius.circular(Y2.rPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mark, size: 13, color: accent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                                queued
                                    ? S.t('In sync queue · saved just now',
                                        'सिंक रांगेत · आत्ताच जतन केले')
                                    : S.t('Saved & syncing · just now',
                                        'जतन केले व सिंक होत आहे · आत्ताच'),
                                style: F.hind(11,
                                    w: FontWeight.w600, color: accent),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton2(
                    label: S.t('Done', 'झाले'),
                    onTap: () => nav.home(),
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
