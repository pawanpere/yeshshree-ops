import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Sync tab — prototype screen [18]. Queue of synced/queued/failed writes with
/// a manual Retry escape hatch; retries automatically when back online. The live
/// retry queue ([retryQueueProvider]) is rendered above the demo rows so real
/// queued posts always appear; the Retry button drains the queue.
class Ui2SyncScreen extends ConsumerStatefulWidget {
  const Ui2SyncScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2SyncScreen> createState() => _Ui2SyncScreenState();
}

class _Ui2SyncScreenState extends ConsumerState<Ui2SyncScreen> {
  // Guards the Retry button against double-taps while the queue is draining.
  bool _draining = false;

  PhoneNav get nav => widget.nav;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

  Future<void> _retry() async {
    if (_draining) return;
    setState(() => _draining = true);
    await ref.read(retryQueueProvider.notifier).drain();
    if (!mounted) return;
    setState(() => _draining = false);
    _snack(S.t('Retrying queued writes…', 'रांगेतील नोंदी पुन्हा पाठवत आहे…'));
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return S.t('just now', 'आत्ताच');
    if (d.inMinutes < 60) return S.t('${d.inMinutes}m ago', '${d.inMinutes} मि पूर्वी');
    if (d.inHours < 24) return S.t('${d.inHours}h ago', '${d.inHours} ता पूर्वी');
    return S.t('${d.inDays}d ago', '${d.inDays} दि पूर्वी');
  }

  /// The queue's rows, derived once from the live retry queue + demo rows, so the
  /// phone list and the desktop table render from a single source.
  List<_SyncRow> _rows(List<dynamic> queue) {
    return [
      // Live queued posts from the retry queue (real offline writes).
      for (final q in queue)
        _SyncRow(
          id: '#${q.body['client_ref']?.toString().substring(0, 4) ?? '----'}',
          label: '${q.label} · ${_ago(q.queuedAt)}',
          word: S.t('Queued', 'रांगेत'),
          fg: Y2.orange,
          bg: Y2.orangeTint,
          line: Y2.orangeLine,
          bad: false,
        ),
      // Demo rows (prototype illustration of synced / queued / failed).
      _SyncRow(
        id: '#4521',
        label: S.t('Output · Press 3 · 132 pcs', 'आउटपुट · प्रेस 3 · 132 pcs'),
        word: S.t('Synced', 'सिंक झाले'),
        fg: Y2.green,
        bg: Y2.greenTint,
        line: Y2.greenLine,
        bad: false,
      ),
      _SyncRow(
        id: '#4522',
        label:
            S.t('Issue · PO 77-2291 · 250 kg', 'इश्यू · PO 77-2291 · 250 kg'),
        word: S.t('Queued', 'रांगेत'),
        fg: Y2.orange,
        bg: Y2.orangeTint,
        line: Y2.orangeLine,
        bad: false,
      ),
      _SyncRow(
        id: '#4523',
        label: S.t(
            'Receipt · Bharat Forge · 1 pc', 'पावती · Bharat Forge · 1 pc'),
        word: S.t('Failed', 'अयशस्वी'),
        fg: Y2.red,
        bg: Y2.redTint,
        line: Y2.redLine,
        bad: true,
        reason: S.t(
            'Server rejected · QC mismatch', 'सर्व्हरने नाकारले · QC जुळत नाही'),
      ),
    ];
  }

  String _summaryLine(int queuedCount, int failedCount, int syncedCount) => S.t(
      '$failedCount failed · $queuedCount queued · $syncedCount synced  ·  last synced 14:31 · auto-retry in 30s',
      '$failedCount अयशस्वी · $queuedCount रांगेत · $syncedCount सिंक  ·  शेवटचा सिंक 14:31 · 30 से मध्ये पुन्हा');

  String get _footerNote => S.t(
      'Retries automatically when online. This is the manual escape hatch — nothing ever silently disappears.',
      'ऑनलाइन आल्यावर आपोआप पुन्हा प्रयत्न होतो. हा फक्त मॅन्युअल पर्याय आहे — काहीही गुपचूप गायब होत नाही.');

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(retryQueueProvider);
    // Demo rows: 1 synced, 1 queued, 1 failed — plus any live queued posts.
    final queuedCount = queue.length + 1;
    const failedCount = 1;
    const syncedCount = 1;
    final rows = _rows(queue);
    final summary = _summaryLine(queuedCount, failedCount, syncedCount);
    return Responsive(
      phone: (_) => _phone(rows, summary),
      desktop: (_) => _desktop(rows, summary),
    );
  }

  // ---- shared header strip (SYNC QUEUE · ONLINE · summary) ----

  Widget _headerStrip(String summary) => Container(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Y2.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(S.t('SYNC QUEUE', 'सिंक रांग'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.khand(17, ls: 0.3, color: Y2.ink)),
                ),
                const Spacer(),
                const SizedBox(width: 8),
                const Icon(I2.online, size: 16, color: Y2.green),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(S.t('ONLINE', 'ऑनलाइन'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.hind(10, w: FontWeight.w600, color: Y2.green)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Queue summary + freshness anchor — the sync screen most needs it.
            Text(summary, style: F.hind(11, color: Y2.muted)),
          ],
        ),
      );

  // ---- phone layout (vertical list of cards) — unchanged ----

  Widget _phone(List<_SyncRow> rows, String summary) {
    return Column(
      children: [
        const StatusBar2(),
        _headerStrip(summary),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 9),
                _item(rows[i]),
              ],
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _footerNote,
                  textAlign: TextAlign.center,
                  style: F.hind(11, color: Y2.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- desktop layout (data table) ----

  Widget _desktop(List<_SyncRow> rows, String summary) {
    return Column(
      children: [
        _headerStrip(summary),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 1200,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                _table(rows),
                const SizedBox(height: 10),
                Text(
                  _footerNote,
                  textAlign: TextAlign.center,
                  style: F.hind(11, color: Y2.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A gap is inserted
  // between every pair of adjacent columns (see _gap) so right-aligned cells /
  // pills never butt up against the next column's text. Total fixed width:
  // _wId + _wStatus + _wAction + 3*_gap = 96 + 130 + 200 + 48 = 474 (≤ 900); the
  // WRITE column is Expanded and absorbs the slack.
  static const _wId = 96.0;
  static const _wStatus = 130.0;
  static const _wAction = 200.0;
  static const _gap = SizedBox(width: 16);

  Widget _table(List<_SyncRow> rows) {
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                SizedBox(width: _wId, child: _th(S.t('REF', 'संदर्भ'))),
                _gap,
                Expanded(child: _th(S.t('WRITE', 'नोंद'))),
                _gap,
                SizedBox(width: _wStatus, child: _th(S.t('STATUS', 'स्थिती'))),
                _gap,
                SizedBox(width: _wAction, child: _th(S.t('ACTION', 'क्रिया'))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s) => Text(s,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRow(_SyncRow r, bool last) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ref (id).
          SizedBox(
            width: _wId,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(r.id,
                  maxLines: 1, style: F.mono(13, color: Y2.ink)),
            ),
          ),
          _gap,
          // Write description + failure reason.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(13, color: Y2.body)),
                if (r.reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(I2.error, size: 13, color: Y2.red),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(r.reason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: F.hind(11, color: Y2.red)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _gap,
          // Status pill.
          SizedBox(
            width: _wStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child:
                    Pill2(text: r.word, fg: r.fg, bg: r.bg, borderColor: r.line),
              ),
            ),
          ),
          _gap,
          // Retry / Edit actions for failed rows; placeholder dash otherwise.
          SizedBox(
            width: _wAction,
            child: r.bad
                ? _actions()
                : Text('—', style: F.mono(13, color: Y2.muted2)),
          ),
        ],
      ),
    );
  }

  Widget _actions() => Row(
        children: [
          // Retry shows an inline spinner + disables while draining.
          Pressable2(
            onTap: _draining ? null : _retry,
            child: Opacity(
              opacity: _draining ? 0.6 : 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Y2.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_draining) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(S.t('Retry', 'पुन्हा'),
                        style: F.hind(12,
                            w: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Edit is not yet wired — de-emphasized so it doesn't read as a live
          // control (matches the phone card's de-emphasis).
          Flexible(
            child: Opacity(
              opacity: 0.45,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCDD6E3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(S.t('Edit', 'संपादित करा'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style:
                        F.hind(12, w: FontWeight.w600, color: Y2.muted)),
              ),
            ),
          ),
        ],
      );

  Widget _item(_SyncRow r) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Y2.card,
          borderRadius: BorderRadius.circular(Y2.rRow),
          border: Border.all(color: Y2.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(r.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.mono(13, color: Y2.ink)),
                ),
                const SizedBox(width: 8),
                // Status as a Pill2, consistent with Home / Cockpit.
                Pill2(text: r.word, fg: r.fg, bg: r.bg, borderColor: r.line),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(r.label, style: F.hind(12, color: Y2.muted)),
            ),
            if (r.reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(I2.error, size: 13, color: Y2.red),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(r.reason!,
                          style: F.hind(11, color: Y2.red)),
                    ),
                  ],
                ),
              ),
            if (r.bad)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    // Retry shows an inline spinner + disables while draining.
                    Pressable2(
                      onTap: _draining ? null : _retry,
                      child: Opacity(
                        opacity: _draining ? 0.6 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Y2.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_draining) ...[
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                ),
                                const SizedBox(width: 7),
                              ],
                              Text(S.t('Retry', 'पुन्हा'),
                                  style: F.hind(12,
                                      w: FontWeight.w600,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Edit is not yet wired — de-emphasized so it doesn't read as
                    // a live control (opening the source form pre-filled is out
                    // of scope; would require importing the source form).
                    Flexible(
                      child: Opacity(
                        opacity: 0.45,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFCDD6E3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(S.t('Edit', 'संपादित करा'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: F.hind(12,
                                  w: FontWeight.w600, color: Y2.muted)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// One row in the sync queue — shared by the phone card list and the desktop
/// table so both render from a single data source.
class _SyncRow {
  const _SyncRow({
    required this.id,
    required this.label,
    required this.word,
    required this.fg,
    required this.bg,
    required this.line,
    required this.bad,
    this.reason,
  });

  final String id;
  final String label;
  final String word;
  final Color fg;
  final Color bg;
  final Color line;
  final bool bad;
  final String? reason;
}
