import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/retry_queue.dart';
import '../../core/strings.dart';
import '../nav.dart';
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

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(retryQueueProvider);
    // Demo rows: 1 synced, 1 queued, 1 failed — plus any live queued posts.
    final queuedCount = queue.length + 1;
    const failedCount = 1;
    const syncedCount = 1;
    return Column(
      children: [
        const StatusBar2(),
        Container(
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
              Text(
                  S.t(
                      '$failedCount failed · $queuedCount queued · $syncedCount synced  ·  last synced 14:31 · auto-retry in 30s',
                      '$failedCount अयशस्वी · $queuedCount रांगेत · $syncedCount सिंक  ·  शेवटचा सिंक 14:31 · 30 से मध्ये पुन्हा'),
                  style: F.hind(11, color: Y2.muted)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            children: [
              // Live queued posts from the retry queue (real offline writes).
              for (final q in queue) ...[
                _item(
                  id: '#${q.body['client_ref']?.toString().substring(0, 4) ?? '----'}',
                  label: '${q.label} · ${_ago(q.queuedAt)}',
                  word: S.t('Queued', 'रांगेत'),
                  fg: Y2.orange,
                  bg: Y2.orangeTint,
                  line: Y2.orangeLine,
                  bad: false,
                ),
                const SizedBox(height: 9),
              ],
              // Demo rows (prototype illustration of synced / queued / failed).
              _item(
                id: '#4521',
                label: S.t('Output · Press 3 · 132 pcs',
                    'आउटपुट · प्रेस 3 · 132 pcs'),
                word: S.t('Synced', 'सिंक झाले'),
                fg: Y2.green,
                bg: Y2.greenTint,
                line: Y2.greenLine,
                bad: false,
              ),
              const SizedBox(height: 9),
              _item(
                id: '#4522',
                label: S.t('Issue · PO 77-2291 · 250 kg',
                    'इश्यू · PO 77-2291 · 250 kg'),
                word: S.t('Queued', 'रांगेत'),
                fg: Y2.orange,
                bg: Y2.orangeTint,
                line: Y2.orangeLine,
                bad: false,
              ),
              const SizedBox(height: 9),
              _item(
                id: '#4523',
                label: S.t('Receipt · Bharat Forge · 1 pc',
                    'पावती · Bharat Forge · 1 pc'),
                word: S.t('Failed', 'अयशस्वी'),
                fg: Y2.red,
                bg: Y2.redTint,
                line: Y2.redLine,
                bad: true,
                reason: S.t('Server rejected · QC mismatch',
                    'सर्व्हरने नाकारले · QC जुळत नाही'),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  S.t(
                      'Retries automatically when online. This is the manual escape hatch — nothing ever silently disappears.',
                      'ऑनलाइन आल्यावर आपोआप पुन्हा प्रयत्न होतो. हा फक्त मॅन्युअल पर्याय आहे — काहीही गुपचूप गायब होत नाही.'),
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

  Widget _item({
    required String id,
    required String label,
    required String word,
    required Color fg,
    required Color bg,
    required Color line,
    required bool bad,
    String? reason,
  }) =>
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
                  child: Text(id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: F.mono(13, color: Y2.ink)),
                ),
                const SizedBox(width: 8),
                // Status as a Pill2, consistent with Home / Cockpit.
                Pill2(text: word, fg: fg, bg: bg, borderColor: line),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(label, style: F.hind(12, color: Y2.muted)),
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(I2.error, size: 13, color: Y2.red),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(reason,
                          style: F.hind(11, color: Y2.red)),
                    ),
                  ],
                ),
              ),
            if (bad)
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
