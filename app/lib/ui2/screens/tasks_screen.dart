import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// A single task row model. [mine] flags rows owned by the current user so the
/// 'Mine' filter can show a subset. Exactly one of [go] / [tab] is set.
class _Task {
  const _Task(this.glyph, this.left, this.title, this.sub,
      {this.go, this.tab, this.mine = false});
  final Widget glyph;
  final Color left;
  final String title;
  final String sub;
  final ScreenId? go;
  final int? tab; // when set, tap switches tab instead of pushing a screen
  final bool mine;
}

/// Tasks tab — prototype screen [32]. The All / Mine filter actually switches
/// state and filters the rendered list (Mine = the current user's subset).
class Ui2TasksScreen extends StatefulWidget {
  const Ui2TasksScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2TasksScreen> createState() => _Ui2TasksScreenState();
}

class _Ui2TasksScreenState extends State<Ui2TasksScreen> {
  int _filterIndex = 0; // 0 = All, 1 = Mine

  PhoneNav get nav => widget.nav;

  // The full task set. Rows flagged [mine] belong to the current user and are
  // the subset shown under 'Mine'.
  List<_Task> get _tasks => [
        _Task(
          const Glyph(GlyphShape.diamond, Y2.red, size: 10),
          Y2.red,
          S.t('Approval waiting', 'मंजुरी प्रतीक्षेत'),
          'Sunita · +250 kg CR coil',
          go: ScreenId.notifications,
          mine: true,
        ),
        _Task(
          const Glyph(GlyphShape.square, Y2.orange, size: 10),
          Y2.orange,
          S.t('Parked output · 2 holds', 'पार्क आउटपुट · 2 होल्ड'),
          S.t('need an order or scrap', 'ऑर्डर किंवा स्क्रॅप हवे'),
          go: ScreenId.confHistory,
          mine: true,
        ),
        _Task(
          const Glyph(GlyphShape.triangle, Y2.orange, size: 10),
          Y2.orange,
          S.t('Unmatched vehicle', 'जुळत नसलेले वाहन'),
          'MH09 KL 2210 · at gate',
          go: ScreenId.unmatched,
        ),
        _Task(
          const Glyph(GlyphShape.ring, Y2.accent, size: 10),
          Y2.accent,
          S.t('Receipt to check', 'तपासायची पावती'),
          'Bharat Forge · QC pending',
          go: ScreenId.gateMatch,
        ),
        _Task(
          const Glyph(GlyphShape.dot, Y2.orange, size: 10),
          Y2.orange,
          S.t('Waiting to sync', 'सिंकच्या प्रतीक्षेत'),
          '1 failed · 1 queued',
          tab: 2,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final all = _tasks;
    final mine = all.where((t) => t.mine).toList();
    final visible = _filterIndex == 0 ? all : mine;
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('TASKS', 'कामे'),
                  style: F.khand(17, ls: 0.3, color: Y2.ink)),
              const SizedBox(height: 9),
              Row(children: [
                _filter(
                    S.t('All · ${all.length}', 'सर्व · ${all.length}'), 0),
                const SizedBox(width: 18),
                _filter(
                    S.t('Mine · ${mine.length}', 'माझे · ${mine.length}'), 1),
              ]),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState2(
                  icon: I2.allClear,
                  title: S.t('Nothing needs you right now',
                      'सध्या तुमची गरज नाही'),
                  subtitle: _filterIndex == 1
                      ? S.t('Tasks assigned to you appear here automatically.',
                          'तुम्हाला दिलेली कामे इथे आपोआप दिसतील.')
                      : S.t('New tasks appear here automatically.',
                          'नवीन कामे इथे आपोआप दिसतील.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  children: [
                    Text(
                        S.t(
                            'Pulled together from work that already exists — not a new list to keep.',
                            'आधीच असलेल्या कामातून एकत्र केलेले — नवीन यादी ठेवायची नाही.'),
                        style: F.hind(11, color: Y2.muted, height: 1.5)),
                    const SizedBox(height: 9),
                    for (final t in visible)
                      _taskCard(t.glyph, t.left, t.title, t.sub, () {
                        if (t.tab != null) {
                          nav.tab(t.tab!);
                        } else if (t.go != null) {
                          nav.go(t.go!);
                        }
                      }),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filter(String label, int i) {
    final active = _filterIndex == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filterIndex = i),
      child: Container(
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: active ? Y2.accent : Colors.transparent, width: 2.5)),
        ),
        child: Text(label,
            style: F.hind(13,
                w: FontWeight.w600, color: active ? Y2.ink : Y2.muted)),
      ),
    );
  }

  Widget _taskCard(Widget glyph, Color left, String title, String sub,
          VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Card2(
          radius: Y2.rRow,
          leftBorder: left,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Row(children: [
                  glyph,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: F.hind(14,
                                w: FontWeight.w600, color: Y2.ink)),
                        Text(sub, style: F.hind(11, color: Y2.muted)),
                      ],
                    ),
                  ),
                ]),
              ),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ),
        ),
      );
}
