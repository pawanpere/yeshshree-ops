import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Confirmation history — prototype screen [33]. Today's posted/queued/synced
/// output confirmations for the line; a posted entry offers a tracked
/// correction. Rows are loaded from [Data.confirmationsHistory]; falls back to
/// clearly-marked DEMO data when the backend is unreachable or the table is
/// empty.
class Ui2ConfHistoryScreen extends StatefulWidget {
  const Ui2ConfHistoryScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2ConfHistoryScreen> createState() => _Ui2ConfHistoryScreenState();
}

class _Ui2ConfHistoryScreenState extends State<Ui2ConfHistoryScreen> {
  Loaded<List<Json>>? _data;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.confirmationsHistory();
    if (!mounted) return;
    setState(() => _data = res);
  }

  /// Numbers arrive as strings — parse to a rounded int.
  int _qty(Object? v) => (double.tryParse('$v') ?? 0).round();

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
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];

    return Column(
      children: [
        const StatusBar2(),
        ScreenHeader2(
          title: S.t('CONFIRMATION HISTORY', 'कन्फर्मेशन इतिहास'),
          subtitle: S.t('today', 'आज'),
          onBack: nav.pop,
          demo: loaded?.demo ?? false,
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: I2.invoice,
                      title: S.t('No confirmations today',
                          'आज कोणतीही नोंद नाही'),
                      subtitle: S.t(
                          'Output you record today will appear here.',
                          'आज नोंदवलेले आउटपुट इथे दिसेल.'),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Shift summary strip — top-line metrics for the log.
                          _summaryStrip(rows),
                          const SizedBox(height: 13),
                          for (int i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: 9),
                            _row(rows[i]),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            S.t(
                                'A correction makes a tracked adjustment with a reason — the original post is never silently changed.',
                                'दुरुस्ती कारणासह नोंदलेला बदल करते — मूळ पोस्ट कधीही गुपचूप बदलली जात नाही.'),
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

  // ---- desktop layout (wide data table) ----

  Widget _desktop() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];

    return Column(
      children: [
        // No StatusBar2 on desktop — the wide chrome starts at the header.
        ScreenHeader2(
          title: S.t('CONFIRMATION HISTORY', 'कन्फर्मेशन इतिहास'),
          subtitle: S.t('today', 'आज'),
          onBack: nav.pop,
          demo: loaded?.demo ?? false,
        ),
        Expanded(
          child: loaded == null
              ? const SkeletonRows(count: 6)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: I2.invoice,
                      title: S.t('No confirmations today',
                          'आज कोणतीही नोंद नाही'),
                      subtitle: S.t(
                          'Output you record today will appear here.',
                          'आज नोंदवलेले आउटपुट इथे दिसेल.'),
                    )
                  : ResponsiveContent(
                      maxWidth: 1200,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _summaryStrip(rows),
                            const SizedBox(height: 14),
                            _table(rows),
                            const SizedBox(height: 10),
                            Text(
                              S.t(
                                  'A correction makes a tracked adjustment with a reason — the original post is never silently changed.',
                                  'दुरुस्ती कारणासह नोंदलेला बदल करते — मूळ पोस्ट कधीही गुपचूप बदलली जात नाही.'),
                              textAlign: TextAlign.center,
                              style: F.hind(11, color: Y2.muted, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  // Column widths shared by the desktop header + rows so the cells line up. A gap
  // is inserted between adjacent columns (see _gap) so right-aligned numbers/pills
  // never butt up against the next column's text.
  static const _wTime = 86.0;
  static const _wId = 84.0;
  static const _wGood = 110.0;
  static const _wRej = 120.0;
  static const _wStatus = 120.0;
  static const _gap = SizedBox(width: 16);

  /// Scale-to-fit wrapper so numeric cells never overflow their fixed column,
  /// whatever the test font metrics.
  Widget _fit(Widget child, {Alignment align = Alignment.centerRight}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

  Widget _table(List<Json> rows) {
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
                _th(_wTime, S.t('Time', 'वेळ')),
                _gap,
                _th(_wId, S.t('Doc #', 'दस्त #')),
                _gap,
                Expanded(child: _th(null, S.t('Material', 'माल'))),
                _gap,
                _th(_wGood, S.t('Good', 'चांगले'), right: true),
                _gap,
                _th(_wRej, S.t('Rejected', 'नाकारले'), right: true),
                _gap,
                _th(_wStatus, S.t('Status', 'स्थिती'), right: true),
              ],
            ),
          ),
          for (int i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(double? w, String label, {bool right = false}) {
    final t = Text(label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));
    return w == null ? t : SizedBox(width: w, child: t);
  }

  Widget _tableRow(Json c, bool last) {
    final name = '${c['material_name'] ?? '—'}';
    final good = _qty(c['good_qty']);
    final rej = _qty(c['rejected_qty']);
    final id = c['id'];

    final sync = '${c['sync_status'] ?? ''}'.toLowerCase();
    final Widget status = switch (sync) {
      'synced' => _statusPill(
          S.t('synced', 'सिंक झाले'), Y2.green, Y2.greenTint, Y2.greenLine),
      'queued' => _statusPill(
          S.t('queued', 'रांगेत'), Y2.orange, Y2.orangeTint, Y2.orangeLine),
      _ => _statusPill(
          S.t('posted', 'पोस्ट केले'), Y2.muted, Y2.lineSoft, Y2.line),
    };

    return Pressable2(
      onTap: () => nav.sheet(SheetId.correction),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border:
              last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _wTime,
              child: _fit(
                Text(_time(c['posted_at']),
                    maxLines: 1,
                    style: F.mono(13, w: FontWeight.w600, color: Y2.body)),
                align: Alignment.centerLeft,
              ),
            ),
            _gap,
            SizedBox(
              width: _wId,
              child: _fit(
                Text('#$id',
                    maxLines: 1,
                    style: F.mono(13, w: FontWeight.w600, color: Y2.muted)),
                align: Alignment.centerLeft,
              ),
            ),
            _gap,
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
            ),
            _gap,
            SizedBox(
              width: _wGood,
              child: _fit(Text(S.t('$good pc', '$good pc'),
                  maxLines: 1,
                  style: F.mono(14, w: FontWeight.w700, color: Y2.ink))),
            ),
            _gap,
            SizedBox(
              width: _wRej,
              child: rej > 0
                  ? _fit(_rejectChip(S.t('$rej reject', '$rej नापास')))
                  : _fit(Text('—',
                      maxLines: 1, style: F.mono(13, color: Y2.muted2))),
            ),
            _gap,
            SizedBox(
              width: _wStatus,
              child: _fit(status),
            ),
          ],
        ),
      ),
    );
  }

  /// Maps one loaded confirmation row to the existing [_entry] design.
  Widget _row(Json c) {
    final name = '${c['material_name'] ?? '—'}';
    final good = _qty(c['good_qty']);
    final rej = _qty(c['rejected_qty']);
    final id = c['id'];

    final sync = '${c['sync_status'] ?? ''}'.toLowerCase();
    final Widget status = switch (sync) {
      'synced' => _statusPill(
          S.t('synced', 'सिंक झाले'), Y2.green, Y2.greenTint, Y2.greenLine),
      'queued' => _statusPill(
          S.t('queued', 'रांगेत'), Y2.orange, Y2.orangeTint, Y2.orangeLine),
      _ => _statusPill(
          S.t('posted', 'पोस्ट केले'), Y2.muted, Y2.lineSoft, Y2.line),
    };

    return _entry(
      title: S.t('$name · $good pc', '$name · $good pc'),
      status: status,
      metaPrefix: '${_time(c['posted_at'])} · #$id',
      reject: rej > 0 ? S.t('$rej reject', '$rej नापास') : null,
    );
  }

  /// Two-digit `HH:mm` parsed from an ISO timestamp; raw string on failure.
  String _time(Object? posted) {
    final raw = '${posted ?? ''}';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final h2 = dt.hour.toString().padLeft(2, '0');
    final m2 = dt.minute.toString().padLeft(2, '0');
    return '$h2:$m2';
  }

  /// Compact "160 pc · 2 rej · 98.8%" summary strip under the header, computed
  /// from the loaded rows.
  Widget _summaryStrip(List<Json> rows) {
    var good = 0;
    var reject = 0;
    for (final c in rows) {
      good += _qty(c['good_qty']);
      reject += _qty(c['rejected_qty']);
    }
    final total = good + reject;
    final yield = total > 0 ? good / total * 100 : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Y2.lineSoft,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Row(
        children: [
          _summaryCell(S.t('$good pc', '$good pc'),
              S.t('confirmed', 'पुष्टी केले'), Y2.ink),
          _summaryDivider(),
          _summaryCell('$reject', S.t('rejects', 'नापास'), Y2.red),
          _summaryDivider(),
          _summaryCell('${yield.toStringAsFixed(1)}%',
              S.t('yield', 'उत्पादन'), Y2.green),
        ],
      ),
    );
  }

  Widget _summaryCell(String value, String label, Color valueColor) => Expanded(
        child: Column(
          children: [
            Text(value, style: F.khand(17, ls: 0.2, color: valueColor)),
            const SizedBox(height: 2),
            Text(label, style: F.hind(10, color: Y2.muted)),
          ],
        ),
      );

  Widget _summaryDivider() =>
      Container(width: 1, height: 26, color: Y2.line);

  Widget _statusPill(String label, Color fg, Color bg, Color border) => Pill2(
        text: label,
        fg: fg,
        bg: bg,
        borderColor: border,
      );

  Widget _entry({
    required String title,
    required Widget status,
    required String metaPrefix,
    String? reject,
    String? flag,
    Color borderColor = Y2.line,
    Widget? action,
  }) =>
      Pressable2(
        onTap: () => nav.sheet(SheetId.correction),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(Y2.rRow),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(title,
                        style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                  ),
                  const SizedBox(width: 8),
                  status,
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(metaPrefix,
                          style: F.hind(11, color: Y2.muted)),
                    ),
                    if (reject != null) ...[
                      const SizedBox(width: 6),
                      _rejectChip(reject),
                    ],
                    if (flag != null) ...[
                      const SizedBox(width: 6),
                      const Icon(I2.warning, size: 13, color: Y2.orange),
                      const SizedBox(width: 3),
                      Text(flag,
                          style: F.hind(11,
                              w: FontWeight.w600, color: Y2.orange)),
                    ],
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
        ),
      );

  /// Small red chip for a reject count so quality flags are scannable.
  Widget _rejectChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Y2.redTint,
          border: Border.all(color: Y2.redLine),
          borderRadius: BorderRadius.circular(Y2.rPill),
        ),
        child: Text(label,
            style: F.hind(10, w: FontWeight.w600, color: Y2.red)),
      );
}
