import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../tokens.dart';

/// Bottom-sheet modal — prototype screen [34] (the "CORRECT PC-2258" sheet).
/// Rendered inside the phone frame as an overlay, not a real OS bottom sheet,
/// so the demo keeps the device illusion.
class CorrectionSheet2 extends StatelessWidget {
  const CorrectionSheet2({super.key, this.onClose, this.onPost});
  final VoidCallback? onClose;
  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CORRECT PC-2258', style: F.khand(18, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 3),
          Text(
              S.t(
                  'This creates a tracked adjustment, not an edit. The original stays on record.',
                  'ही नोंदवलेली दुरुस्ती आहे, संपादन नाही. मूळ नोंद कायम राहते.'),
              style: F.hind(12, color: Y2.body)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _valBox(S.t('Was', 'होते'), '52', false)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('→', style: F.hind(14, color: Y2.muted)),
              ),
              Expanded(
                  child: _valBox(S.t('Corrected to', 'दुरुस्त केले'), '48', true)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              border: Border.all(color: Y2.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    S.t('Reason · Miscount at handover',
                        'कारण · हस्तांतरणात चुकीची मोजणी'),
                    style: F.hind(13, color: Y2.body)),
                Text('▾', style: F.hind(13, color: Y2.muted)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCDD6E3)),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(S.t('Cancel', 'रद्द करा'),
                        style:
                            F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 13,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPost ?? onClose,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Y2.accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(S.t('Post adjustment', 'नोंद करा'),
                        style: F.hind(14,
                            w: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valBox(String label, String value, bool accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accent ? Colors.white : const Color(0xFFF6F8FB),
          border: Border.all(
              color: accent ? Y2.accent : Y2.line, width: accent ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: F.hind(10, w: FontWeight.w400, color: Y2.muted)),
            Text(value,
                style: F.mono(20, color: accent ? Y2.accent : Y2.ink)),
          ],
        ),
      );
}
