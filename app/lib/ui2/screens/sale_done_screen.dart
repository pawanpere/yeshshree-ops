import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Sale invoiced — success state, prototype screen [23]. Shows the real
/// submitted invoice doc number, total, and customer carried over from the sale
/// form via [Ui2Flow] (falling back to the prototype literals when absent).
class Ui2SaleDoneScreen extends StatefulWidget {
  const Ui2SaleDoneScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2SaleDoneScreen> createState() => _Ui2SaleDoneScreenState();
}

class _Ui2SaleDoneScreenState extends State<Ui2SaleDoneScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
  }

  // Formats the stashed amount; when absent, falls back to a neutral phrase
  // rather than a fabricated total that can't be reproduced from the inputs.
  String _money(String? raw, String fallback) {
    if (raw == null) return fallback;
    final v = double.tryParse(raw);
    if (v == null) return raw;
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₹${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    final doc = '${Ui2Flow.raw('sale.doc') ?? 'INV-2326'}';
    final customer = Ui2Flow.get<String>('sale.customer') ?? 'Sunrise Metals';
    final amount = _money(
        Ui2Flow.get<String>('sale.amount'), S.t('the total', 'एकूण रक्कम'));
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
                const Center(child: _SuccessHero()),
                const SizedBox(height: 20),
                Text(S.t('INVOICE RAISED', 'इन्व्हॉइस तयार झाले'),
                    textAlign: TextAlign.center,
                    style: F.khand(22, ls: 0.4, color: Y2.ink)),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    style: F.hind(13, color: Y2.body, height: 1.5),
                    children: [
                      TextSpan(text: S.t('Invoice ', 'इन्व्हॉइस ')),
                      TextSpan(text: doc, style: F.mono(13, color: Y2.ink)),
                      TextSpan(
                          text: S.t(
                              ' · $amount to $customer. GST filed & posted to SAP.',
                              ' · $amount $customer ला. GST भरले व SAP ला पोस्ट केले.')),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                PrimaryButton2(
                  label: S.t('Back to home', 'मुख्यपृष्ठावर परत'),
                  onTap: () => nav.home(),
                ),
              ],
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
