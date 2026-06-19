import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Alerts tab — prototype screen [26]. Loads notifications from the backend
/// (falls back to DEMO), filters Unread / All, and lets the supervisor
/// Allow / Decline the override-approval card (POST /approvals/1/decide) with an
/// optimistic resolve.
class Ui2NotificationsScreen extends StatefulWidget {
  const Ui2NotificationsScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2NotificationsScreen> createState() => _Ui2NotificationsScreenState();
}

class _Ui2NotificationsScreenState extends State<Ui2NotificationsScreen> {
  int _tab = 0; // 0 = Unread, 1 = All

  Loaded<List<Json>>? _data;

  // Approval card local state: null = pending, otherwise 'approve' | 'decline'.
  String? _approvalDecision;
  bool _approvalBusy = false;
  // Which button is mid-flight, so only the pressed one shows a spinner.
  String? _pendingDecision;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.notifications();
    if (!mounted) return;
    setState(() => _data = res);
  }

  Future<void> _decide(String decision) async {
    if (_approvalBusy || _approvalDecision != null) return;
    setState(() {
      _approvalBusy = true;
      _pendingDecision = decision;
    });
    final res =
        await Data.mutate('/approvals/1/decide', {'decision': decision});
    if (!mounted) return;
    if (res.failed) {
      setState(() {
        _approvalBusy = false;
        _pendingDecision = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error?.message ??
            S.t('Could not record decision', 'निर्णय नोंदवता आला नाही')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    // Success: light haptic + a receipt toast for the consequential decision.
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(decision == 'approve'
          ? S.t('Approved +250 kg for Sunita',
              'सुनितासाठी +250 kg मंजूर केले')
          : S.t('Declined the request', 'विनंती नाकारली')),
      behavior: SnackBarBehavior.floating,
    ));
    // Optimistically mark the card resolved (the reminders stop, card collapses).
    setState(() {
      _approvalBusy = false;
      _pendingDecision = null;
      _approvalDecision = decision;
    });
  }

  // Unread count drives the segment label. The approval card counts as unread
  // until it is resolved.
  int get _unreadCount {
    final rows = _data?.data ?? const <Json>[];
    var n = rows.where((r) => r['unread'] == true).length;
    if (rows.isEmpty) n = 3; // matches the prototype's default
    if (_approvalDecision != null && n > 0) n -= 1;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final loading = _data == null;
    final demo = _data?.demo ?? false;
    final cards = loading ? const <Widget>[] : _cards();
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
              Row(
                children: [
                  Text(S.t('ALERTS', 'सूचना'),
                      style: F.khand(17, ls: 0.3, color: Y2.ink)),
                  if (demo) ...[
                    const SizedBox(width: 8),
                    const DemoChip(),
                  ],
                ],
              ),
              const SizedBox(height: 9),
              Row(children: [
                _seg(S.t('Unread $_unreadCount', 'न वाचलेले $_unreadCount'), 0),
                const SizedBox(width: 18),
                _seg(S.t('All', 'सर्व'), 1),
              ]),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const SkeletonRows(count: 3)
              : cards.isEmpty
                  ? EmptyState2(
                      icon: I2.allClear,
                      title: _tab == 0
                          ? S.t("You're all caught up", 'सर्व पाहून झाले')
                          : S.t('No alerts yet', 'अद्याप सूचना नाहीत'),
                      subtitle: _tab == 0
                          ? S.t('No unread alerts', 'न वाचलेल्या सूचना नाहीत')
                          : S.t('New alerts appear here.',
                              'नवीन सूचना इथे दिसतील.'),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      children: cards,
                    ),
        ),
        BottomTabs2(active: 3, onTap: nav.tab),
      ],
    );
  }

  List<Widget> _cards() {
    final cards = <Widget>[];
    // The approval card shows while pending; when resolved it shows a compact
    // resolved chip, and is hidden entirely in the Unread filter.
    if (_approvalDecision == null) {
      cards
        ..add(_permissionCard())
        ..add(const SizedBox(height: 9));
    } else if (_tab == 1) {
      cards
        ..add(_resolvedCard())
        ..add(const SizedBox(height: 9));
    }

    // Line-B alert is unread; schedule alert is read. The Unread filter drops
    // the read one.
    cards.add(_alert(
      const Glyph(GlyphShape.triangle, Y2.orange, size: 11),
      S.t('Line B behind plan', 'लाइन B प्लॅनमागे'),
      S.t('84% at 2 pm · tap to view', '2 pm ला 84% · पाहण्यासाठी टॅप करा'),
      () => nav.go(ScreenId.cockpit),
      unread: true,
      time: S.t('12m ago', '12 मि पूर्वी'),
    ));

    if (_tab == 1) {
      cards
        ..add(const SizedBox(height: 9))
        ..add(_alert(
          const Glyph(GlyphShape.ring, Y2.muted, size: 11),
          S.t('Schedule wk-25 released', 'wk-25 शेड्यूल जारी झाले'),
          S.t('by Anil · 1:10 pm', 'अनिल कडून · 1:10 pm'),
          () {},
          unread: false,
          time: S.t('1h ago', '1 ता पूर्वी'),
        ));
    }
    return cards;
  }

  Widget _seg(String label, int i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: _tab == i ? Y2.accent : Colors.transparent,
                    width: 2.5)),
          ),
          child: Text(label,
              style: F.hind(13,
                  w: FontWeight.w600, color: _tab == i ? Y2.ink : Y2.muted)),
        ),
      );

  Widget _resolvedCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Y2.line),
        ),
        child: Row(
          children: [
            Icon(
                _approvalDecision == 'approve' ? I2.checkCircle : I2.close,
                size: 18,
                color: _approvalDecision == 'approve' ? Y2.green : Y2.muted),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      S.t('Permission — extra issue',
                          'परवानगी — अतिरिक्त इश्यू'),
                      style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  Text(
                      _approvalDecision == 'approve'
                          ? S.t('Allowed', 'मंजूर केले')
                          : S.t('Declined', 'नाकारले'),
                      style: F.hind(12, color: Y2.muted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _permissionCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Y2.redTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Y2.redLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Glyph(GlyphShape.diamond, Y2.red, size: 11),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          S.t('Permission needed — extra issue',
                              'परवानगी हवी — अतिरिक्त इश्यू'),
                          style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                      Text(
                          S.t("Sunita asks for +250 kg CR coil over today's limit",
                              'सुनिता आजच्या मर्यादेपेक्षा +250 kg CR coil मागत आहे'),
                          style: F.hind(12, color: Y2.body)),
                      const SizedBox(height: 10),
                      Row(children: [
                        _action(S.t('Allow', 'मंजूर'), Y2.accent, Colors.white,
                            null, 'approve'),
                        const SizedBox(width: 8),
                        _action(S.t('Decline', 'नाकारा'), Colors.white, Y2.ink,
                            const Color(0xFFCDD6E3), 'decline'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                S.t('KEEPS REMINDING UNTIL YOU ACT',
                    'कृती करेपर्यंत आठवण करत राहील'),
                style: F.hind(10, w: FontWeight.w500, ls: 0.3, color: Y2.red)),
          ],
        ),
      );

  Widget _action(String label, Color bg, Color fg, Color? borderColor,
          String decision) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _approvalBusy ? null : () => _decide(decision),
        child: Opacity(
          opacity: _approvalBusy ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingDecision == decision) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(label,
                    style: F.hind(13, w: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      );

  Widget _alert(Widget glyph, String title, String sub, VoidCallback onTap,
          {required bool unread, String? time}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Y2.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unread accent dot at the leading edge (placeholder keeps align).
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 7),
                child: unread
                    ? const Glyph(GlyphShape.dot, Y2.accent, size: 7)
                    : const SizedBox(width: 7),
              ),
              Padding(padding: const EdgeInsets.only(top: 3), child: glyph),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: F.hind(14,
                            w: unread ? FontWeight.w700 : FontWeight.w600,
                            color: Y2.ink)),
                    Text(sub, style: F.hind(12, color: Y2.muted)),
                  ],
                ),
              ),
              if (time != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(time, style: F.hind(10, color: Y2.muted)),
                ),
              ],
            ],
          ),
        ),
      );
}
