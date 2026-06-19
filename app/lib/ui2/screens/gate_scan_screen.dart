import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/frame.dart';
import '../widgets/polish2.dart';

/// Gate — scan challan QR — prototype screen [12]. A full-bleed camera
/// viewfinder (tap to capture) with a "type the number instead" fallback.
/// Both the capture tap and the type fallback advance to the scanned read-back
/// (`gateScanned`), where the lifted values are confirmed before matching.
class Ui2GateScanScreen extends StatefulWidget {
  const Ui2GateScanScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateScanScreen> createState() => _Ui2GateScanScreenState();
}

class _Ui2GateScanScreenState extends State<Ui2GateScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan;
  bool _torch = false;
  bool _captured = false;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  void _capture() {
    if (_captured) return;
    setState(() => _captured = true); // flash the reticle green
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) nav.replace(ScreenId.gateScanned);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StatusBar2(),
        // Header: back chevron · SCAN · 2/6
        ScreenHeader2(
          title: S.t('SCAN', 'स्कॅन'),
          onBack: nav.pop,
          trailing: Text('2/6', style: F.mono(12, color: Y2.muted)),
        ),
        // Viewfinder — full-bleed navy, tap anywhere to capture.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _capture,
            child: ColoredBox(
              color: Y2.navy,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Reticle: dimmed surround + corner brackets + scan line.
                  SizedBox(
                    width: 188,
                    height: 188,
                    child: Stack(
                      children: [
                        // Dimmed scrim around the viewfinder window.
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x8C11243F),
                                  blurRadius: 0,
                                  spreadRadius: 9999),
                            ],
                          ),
                        ),
                        // 4 L-shaped corner brackets.
                        ..._corners(_captured ? Y2.green : Y2.accent),
                        // Animated horizontal scan line.
                        if (!_captured)
                          AnimatedBuilder(
                            animation: _scan,
                            builder: (context, _) => Positioned(
                              left: 12,
                              right: 12,
                              top: 12 + (188 - 24) * _scan.value,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  color: Y2.accent,
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x661D4ED8),
                                        blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Torch toggle (top-right corner of the viewfinder).
                  Positioned(
                    top: 18,
                    right: 18,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _torch = !_torch);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _torch
                              ? const Color(0x33FFFFFF)
                              : const Color(0x1AFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _torch
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          size: 20,
                          color: _torch
                              ? Colors.white
                              : const Color(0xFFAEBFD6),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 16,
                    right: 16,
                    child: Text(
                      S.t('point at the challan QR · tap to capture',
                          'चलन QR कडे धरा · कॅप्चर करण्यासाठी टॅप करा'),
                      textAlign: TextAlign.center,
                      style: F.hind(13, color: const Color(0xFFAEBFD6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Footer — "type the number instead" fallback.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8FB),
            border: Border(top: BorderSide(color: Y2.line)),
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => nav.replace(ScreenId.gateScanned),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCDD6E3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.keyboard_outlined,
                          size: 17, color: Y2.ink),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                            S.t('Type the number instead',
                                'त्याऐवजी नंबर टाइप करा'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style:
                                F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.t('works offline · matched on sync',
                    'ऑफलाइन चालते · सिंकवर जुळते'),
                textAlign: TextAlign.center,
                style: F.hind(11, color: Y2.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 4 L-shaped corner brackets framing the viewfinder window.
  List<Widget> _corners(Color c) {
    const len = 26.0;
    const thick = 3.0;
    Widget bracket({
      double? left,
      double? right,
      double? top,
      double? bottom,
      required bool isTop,
      required bool isLeft,
    }) =>
        Positioned(
          left: left,
          right: right,
          top: top,
          bottom: bottom,
          child: SizedBox(
            width: len,
            height: len,
            child: Stack(
              children: [
                // Horizontal arm.
                Positioned(
                  left: 0,
                  right: 0,
                  top: isTop ? 0 : null,
                  bottom: isTop ? null : 0,
                  child: Container(height: thick, color: c),
                ),
                // Vertical arm.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: isLeft ? 0 : null,
                  right: isLeft ? null : 0,
                  child: Container(width: thick, color: c),
                ),
              ],
            ),
          ),
        );

    return [
      bracket(left: 6, top: 6, isTop: true, isLeft: true),
      bracket(right: 6, top: 6, isTop: true, isLeft: false),
      bracket(left: 6, bottom: 6, isTop: false, isLeft: true),
      bracket(right: 6, bottom: 6, isTop: false, isLeft: false),
    ];
  }
}
