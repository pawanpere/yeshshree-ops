import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Store · Issue — over-limit approval granted — prototype screen [09].
/// Centered confirmation: Ramesh approved the extra kg; operator can now issue
/// the full amount. Continue replaces forward into the issue-done step.
class Ui2IssueApprovedScreen extends StatefulWidget {
  const Ui2IssueApprovedScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2IssueApprovedScreen> createState() => _Ui2IssueApprovedScreenState();
}

class _Ui2IssueApprovedScreenState extends State<Ui2IssueApprovedScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final qty = Ui2Flow.get<int>('issue.qty') ?? 250;
    final over = Ui2Flow.get<int>('issue.over') ?? 50;
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Row(
            children: [
              const Icon(I2.check, size: 18, color: Y2.green),
              const SizedBox(width: 7),
              Expanded(
                child: Text(S.t('APPROVED · KG OK', 'मंजूर · KG ठीक'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: F.khand(17, ls: 0.3, color: Y2.green)),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 70),
                  const _SuccessHero(),
                  const SizedBox(height: 20),
                  Text(
                    S.t('APPROVED · $qty KG OK', 'मंजूर · $qty KG ठीक'),
                    textAlign: TextAlign.center,
                    style: F.khand(22, ls: 0.4, color: Y2.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.t(
                        'Ramesh allowed the extra $over kg. You can issue the full amount now — the approval is attached.',
                        'रमेशने अतिरिक्त $over kg मंजूर केले. आता तुम्ही पूर्ण रक्कम इश्यू करू शकता — मंजुरी जोडलेली आहे.'),
                    textAlign: TextAlign.center,
                    style: F.hind(13, color: Y2.body, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton2(
                      label: S.t('Issue $qty kg', '$qty kg इश्यू करा'),
                      onTap: () => nav.replace(ScreenId.issueDone),
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
