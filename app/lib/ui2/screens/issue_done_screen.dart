import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Material-issued success screen — prototype screen [10]. Shows the real
/// submitted quantity / material / destination (and doc id if the server
/// returned one), falling back to the prototype literals when nothing was
/// stashed in [Ui2Flow].
class Ui2IssueDoneScreen extends StatefulWidget {
  const Ui2IssueDoneScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2IssueDoneScreen> createState() => _Ui2IssueDoneScreenState();
}

class _Ui2IssueDoneScreenState extends State<Ui2IssueDoneScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final qty = Ui2Flow.get<int>('issue.qty') ?? 250;
    final material =
        Ui2Flow.get<String>('issue.material') ?? 'CR coil 2.5mm';
    final dest = Ui2Flow.get<String>('issue.dest') ??
        S.t('Line A · Press 3', 'लाइन A · प्रेस 3');
    final doc = Ui2Flow.raw('issue.doc');
    final docSuffix = doc != null ? ' · $doc' : '';

    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _SuccessHero(),
                  const SizedBox(height: 20),
                  Text(S.t('MATERIAL ISSUED', 'माल इश्यू झाला'),
                      textAlign: TextAlign.center,
                      style: F.khand(22, ls: 0.4, color: Y2.ink)),
                  const SizedBox(height: 8),
                  Text(
                    S.t(
                        '$qty kg $material issued to $dest$docSuffix. Stock and SAP updated.',
                        '$qty kg $material $dest ला इश्यू केले$docSuffix. स्टॉक व SAP अपडेट झाले.'),
                    textAlign: TextAlign.center,
                    style: F.hind(13, color: Y2.body, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton2(
                      label: S.t('Back to home', 'मुख्यपृष्ठावर परत'),
                      onTap: nav.home,
                    ),
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

/// Animated success ring — scales + fades in once on mount.
class _SuccessHero extends StatelessWidget {
  const _SuccessHero();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      ),
      child: const Icon(I2.checkCircle, size: 64, color: Y2.green),
    );
  }
}
