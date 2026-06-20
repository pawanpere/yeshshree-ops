import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Gate — received & in stock confirmation — prototype screen [17].
/// Terminal success state after GRN is posted to SAP. Reads the stashed
/// [Ui2Flow] gate values (GRN doc id, received qty, location) to show the real
/// submitted numbers, falling back to the prototype literals when absent.
class Ui2GateReceivedScreen extends StatefulWidget {
  const Ui2GateReceivedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateReceivedScreen> createState() => _Ui2GateReceivedScreenState();
}

class _Ui2GateReceivedScreenState extends State<Ui2GateReceivedScreen> {
  late final String _postedAt;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    final now = DateTime.now();
    _postedAt =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final grnDoc = '${Ui2Flow.raw('gate.grnDoc') ?? 'GR-5572'}';
    final received = Ui2Flow.get<String>('gate.received') ?? '3,980';
    final location = Ui2Flow.get<String>('gate.location') ?? 'Store A · Rack 12';
    final queued = Ui2Flow.get<bool>('gate.queued') ?? false;
    // Receipt unit (kg for raw material, pcs for counted components), stashed by
    // the GRN step before it cleared the category — so a component receipt reads
    // "1,500 pcs added" rather than mislabelling it as kg.
    final unit = Ui2Flow.get<String>('gate.receivedUnit') ?? 'kg';
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                          border: Border.all(color: Y2.green, width: 3),
                        ),
                        child: const Icon(I2.check, color: Y2.green, size: 38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    queued
                        ? S.t('SAVED · WILL SYNC', 'जतन केले · सिंक होईल')
                        : S.t('RECEIVED & IN STOCK', 'मिळाले आणि स्टॉकमध्ये'),
                    textAlign: TextAlign.center,
                    style: F.khand(22, ls: 0.4, color: Y2.ink),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: F.hind(13, color: Y2.body, height: 1.5),
                      children: [
                        TextSpan(text: S.t('GRN ', 'GRN ')),
                        TextSpan(
                            text: grnDoc,
                            style: F.mono(13, color: Y2.ink, height: 1.5)),
                        TextSpan(
                            text: queued
                                ? S.t(
                                    ' queued for SAP. $received $unit added to $location.',
                                    ' SAP साठी रांगेत. $received $unit $location मध्ये जोडले.')
                                : S.t(
                                    ' posted to SAP. $received $unit added to $location.',
                                    ' SAP मध्ये पोस्ट केले. $received $unit $location मध्ये जोडले.')),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(S.t('Posted at $_postedAt', '$_postedAt वाजता नोंदले'),
                      textAlign: TextAlign.center,
                      style: F.mono(12, color: Y2.muted)),
                  const SizedBox(height: 24),
                  PrimaryButton2(
                    label: S.t('Next vehicle', 'पुढील वाहन'),
                    onTap: () => nav.replace(ScreenId.gateArrivals),
                  ),
                  const SizedBox(height: 10),
                  OutlineButton2(
                    label: S.t('Back to home', 'मुख्यपृष्ठावर परत'),
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
