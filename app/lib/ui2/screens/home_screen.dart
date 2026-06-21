import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Operator Home tab — prototype screen [01].
///
/// Phone: the original single-column stack (status bar + greeting + the primary
/// "record output" hero, the two secondary actions, then the NEEDS YOU stat
/// tiles). Desktop: the same pieces, but the greeting becomes the screen's own
/// header band and the body lays the hero across the top with the secondary
/// actions and the two NEEDS YOU tiles arranged in a width-driven grid, capped
/// to a centered content column. Both branches reuse the same sub-widgets, so
/// the phone view behaves exactly as before.
class Ui2HomeScreen extends StatelessWidget {
  const Ui2HomeScreen({super.key, required this.nav, this.online = true});
  final PhoneNav nav;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // ---- phone layout (unchanged) ----

  Widget _phone() {
    return Column(
      children: [
        const StatusBar2(),
        _greeting(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _primary(),
                const SizedBox(height: 12),
                _secondary(
                  S.t('Issue material', 'माल इश्यू करा'),
                  Text('STORE', style: F.mono(12, color: Y2.muted)),
                  () => nav.go(ScreenId.issueForm),
                ),
                const SizedBox(height: 12),
                _secondary(
                  S.t('Gate — incoming', 'गेट — आवक'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Glyph(GlyphShape.ring, Y2.accent, size: 9),
                    const SizedBox(width: 6),
                    Text('4 waiting',
                        style:
                            F.hind(11, w: FontWeight.w600, color: Y2.accent)),
                  ]),
                  () => nav.go(ScreenId.gateArrivals),
                ),
                const SizedBox(height: 14),
                Text(S.t('NEEDS YOU', 'तुमची गरज'),
                    style: F.hind(11,
                        w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _holdsTile()),
                  const SizedBox(width: 11),
                  Expanded(child: _overPlanTile()),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Greeting band (operator + shift on the left, sync state on the right).
  /// Shared by both layouts: on phone it is the strip under the status bar; on
  /// desktop it stands in as the screen's own header.
  Widget _greeting() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('Hi Ramesh', 'नमस्कार रमेश'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.khand(22, ls: 0.3, height: 1, color: Y2.ink)),
                  Text(
                      S.t('Shift B · 2–10 pm · Line A',
                          'शिफ्ट B · 2–10 pm · Line A'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.hind(12, color: Y2.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (online)
                    Pill2(
                        text: S.t('SYNCED', 'सिंक झाले'),
                        fg: Y2.green,
                        bg: Y2.greenTint,
                        borderColor: Y2.greenLine)
                  else
                    Pill2(
                        text: S.t('OFFLINE', 'ऑफलाइन'),
                        fg: Y2.orange,
                        bg: Y2.orangeTint,
                        borderColor: Y2.orangeLine),
                  const SizedBox(height: 4),
                  // Freshness anchor so the operator can trust the data is live.
                  Text(
                      online
                          ? S.t('last synced 2m ago', '2 मि पूर्वी सिंक')
                          : S.t('last synced 14:05', 'शेवटचा सिंक 14:05'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: F.hind(10, color: Y2.muted)),
                ],
              ),
            ),
          ],
        ),
      );

  // ---- desktop layout ----

  Widget _desktop() {
    return Column(
      children: [
        // No StatusBar2 on desktop — the greeting band is the screen header.
        _greeting(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: ResponsiveContent(
              maxWidth: 1200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero action spans the full content width.
                  _primary(),
                  const SizedBox(height: 16),
                  // Secondary actions side by side (collapse to one column when
                  // narrow). Self-sizing tiles, so the grid is safe here.
                  CardGrid2(
                    minTileWidth: 320,
                    maxColumns: 2,
                    gap: 16,
                    children: [
                      _secondary(
                        S.t('Issue material', 'माल इश्यू करा'),
                        Text('STORE', style: F.mono(12, color: Y2.muted)),
                        () => nav.go(ScreenId.issueForm),
                      ),
                      _secondary(
                        S.t('Gate — incoming', 'गेट — आवक'),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Glyph(GlyphShape.ring, Y2.accent, size: 9),
                          const SizedBox(width: 6),
                          Text('4 waiting',
                              style: F.hind(11,
                                  w: FontWeight.w600, color: Y2.accent)),
                        ]),
                        () => nav.go(ScreenId.gateArrivals),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(S.t('NEEDS YOU', 'तुमची गरज'),
                      style: F.hind(11,
                          w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
                  const SizedBox(height: 10),
                  // The two attention tiles as a width-driven grid (2-up on
                  // wide, 1-up when the box is narrow).
                  CardGrid2(
                    minTileWidth: 240,
                    maxColumns: 2,
                    gap: 16,
                    children: [
                      _holdsTile(),
                      _overPlanTile(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- shared NEEDS YOU tiles ----

  Widget _holdsTile() => _statTile(
        const Glyph(GlyphShape.diamond, Y2.red, size: 11),
        '2',
        S.t('holds', 'होल्ड्स'),
        () => nav.tab(1),
      );

  Widget _overPlanTile() => _statTile(
        const Glyph(GlyphShape.triangle, Y2.orange, size: 11),
        '1',
        S.t('over plan', 'प्लॅनपेक्षा जास्त'),
        () => nav.go(ScreenId.cockpit),
      );

  Widget _primary() => Pressable2(
        onTap: () => nav.go(ScreenId.confirmForm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: Y2.accent,
            borderRadius: BorderRadius.circular(Y2.rPrimary),
            boxShadow: Y2.shPrimary,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('Record output', 'आउटपुट नोंदवा'),
                        style: F.khand(22,
                            ls: 0.5, height: 1, color: Colors.white)),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(S.t('your main job', 'तुमचे मुख्य काम'),
                          style: F.hind(12,
                              color: Colors.white.withValues(alpha: 0.85))),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(I2.arrowForward, size: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      );

  Widget _secondary(String title, Widget trailing, VoidCallback onTap) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(Y2.rIssue),
            border: Border.all(color: Y2.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: F.hind(16, w: FontWeight.w600, color: Y2.ink)),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      );

  Widget _statTile(Widget glyph, String value, String label,
          VoidCallback onTap) =>
      Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(Y2.rCard),
            border: Border.all(color: Y2.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                glyph,
                const SizedBox(width: 7),
                Text(value, style: F.mono(36, height: 0.8, color: Y2.ink)),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: F.hind(11, color: Y2.muted)),
              ),
            ],
          ),
        ),
      );
}
