import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Gate pass ready — prototype screen [21]. Centered success state with a
/// scannable pass code shown for the gate. The pass id, vehicle and DO are read
/// from [Ui2Flow] (stashed by the dispatch detail screen) and fall back to the
/// prototype literals when nothing was staged.
class Ui2GatePassScreen extends StatefulWidget {
  const Ui2GatePassScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GatePassScreen> createState() => _Ui2GatePassScreenState();
}

class _Ui2GatePassScreenState extends State<Ui2GatePassScreen> {
  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    HapticFeedback.lightImpact();
  }

  void _copyPass(String pass) {
    Clipboard.setData(ClipboardData(text: pass));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.t('Pass $pass copied', 'पास $pass कॉपी केला')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pass = '${Ui2Flow.get<String>('dispatch.pass') ?? 'GP-2208'}';
    final vehicle =
        '${Ui2Flow.get<String>('dispatch.vehicle') ?? 'MH12 GH 7781'}';
    final doNo = '${Ui2Flow.get<String>('dispatch.do') ?? 'DO-3391'}';
    return Column(
      children: [
        const StatusBar2(),
        Expanded(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 640),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        builder: (context, v, child) => Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: Transform.scale(scale: v, child: child),
                        ),
                        child: const Icon(I2.checkCircle,
                            size: 74, color: Y2.green),
                      ),
                      const SizedBox(height: 20),
                      Text(S.t('GATE PASS READY', 'गेट पास तयार'),
                          textAlign: TextAlign.center,
                          style: F.khand(22, ls: 0.4, color: Y2.ink)),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          style: F.hind(13, color: Y2.body, height: 1.5),
                          children: [
                            TextSpan(text: S.t('Pass ', 'पास ')),
                            TextSpan(
                                text: pass,
                                style: F.mono(13, color: Y2.navy)),
                            TextSpan(
                                text: S.t(
                                    ' issued for $vehicle. Delivery ',
                                    ' $vehicle साठी जारी. डिलिव्हरी ')),
                            TextSpan(
                                text: doNo,
                                style: F.mono(13, color: Y2.navy)),
                            TextSpan(
                                text:
                                    S.t(' posted to SAP.', ' SAP वर पोस्ट केली.')),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Y2.navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QrCode(seed: pass),
                            const SizedBox(height: 10),
                            // Copyable pass id
                            Pressable2(
                              haptic: false,
                              onTap: () => _copyPass(pass),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(pass,
                                      style: F.mono(13, color: Colors.white)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.copy_rounded,
                                      size: 14, color: Y2.muted2),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                                S.t('show at gate · valid today',
                                    'गेटवर दाखवा · आज वैध'),
                                style: F.mono(11, color: Y2.muted2)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
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
          ),
        ),
      ],
    );
  }
}

/// 7×7 QR-style code. The fill pattern is derived deterministically from the
/// pass id so the grid encodes the real pass code instead of a fixed literal,
/// while preserving the prototype's 7×7 navy/white shape.
class _QrCode extends StatelessWidget {
  const _QrCode({required this.seed});

  final String seed;

  List<bool> _pattern() {
    // Deterministic pseudo-random fill seeded by the pass id's code units, with
    // the three finder-corner anchors forced on (top-left, top-right,
    // bottom-left) so it always reads like a QR symbol.
    var h = 2166136261; // FNV-1a basis
    for (final c in seed.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0x7fffffff;
    }
    final cells = List<bool>.filled(49, false);
    for (var i = 0; i < 49; i++) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      cells[i] = ((h >> 16) & 1) == 1;
    }
    bool corner(int r, int c) => (r < 2 && c < 2) ||
        (r < 2 && c > 4) ||
        (r > 4 && c < 2);
    for (var r = 0; r < 7; r++) {
      for (var c = 0; c < 7; c++) {
        if (corner(r, c)) cells[r * 7 + c] = true;
      }
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final cells = _pattern();
    return Container(
      width: 120,
      height: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: GridView.count(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final on in cells)
            ColoredBox(color: on ? Y2.navy : Colors.transparent),
        ],
      ),
    );
  }
}
