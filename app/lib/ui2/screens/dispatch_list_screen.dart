import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../data/flow.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/polish2.dart';

/// Dispatch list — prototype screen [19]. Open delivery orders loaded from
/// `Data.dispatches()` (falls back to DEMO when the backend is unreachable or
/// empty). The first READY order gets the accent border, the rest are plain
/// rows. Tapping any DO stashes its id/customer into [Ui2Flow] and opens the
/// build/detail flow; the footer button starts a new dispatch.
class Ui2DispatchListScreen extends StatefulWidget {
  const Ui2DispatchListScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2DispatchListScreen> createState() => _Ui2DispatchListScreenState();
}

class _Ui2DispatchListScreenState extends State<Ui2DispatchListScreen> {
  PhoneNav get nav => widget.nav;

  Loaded<List<Json>>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.dispatches();
    if (!mounted) return;
    setState(() => _data = res);
  }

  /// Stash the chosen DO + customer for the detail screen, then navigate.
  void _open(Json row) {
    Ui2Flow.set('dispatch.do', row['do']);
    Ui2Flow.set('dispatch.customer', row['customer']);
    nav.go(ScreenId.dispatchDetail);
  }

  /// Bilingual sub-line for a DO row ("<customer> · <detail>").
  String _sub(Json row) {
    final customer = '${row['customer'] ?? ''}';
    final detail = '${row['detail'] ?? ''}';
    return S.t('$customer · $detail', '$customer · $detail');
  }

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
    final rows = _data?.data ?? const <Json>[];
    final demo = _data?.demo ?? false;
    return Column(
      children: [
        const StatusBar2(),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 16, 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Y2.line))),
          child: Row(
            children: [
              BackButton2(onTap: nav.pop),
              Text(S.t('DISPATCH', 'डिस्पॅच'),
                  style: F.khand(17, ls: 0.3, color: Y2.ink)),
              const Spacer(),
              if (demo) ...[
                const DemoChip(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(S.t('${rows.length} open', '${rows.length} खुले'),
                    style: F.hind(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false),
              ),
            ],
          ),
        ),
        Expanded(
          child: _data == null
              ? const SkeletonRows(count: 4)
              : rows.isEmpty
                  ? EmptyState2(
                      icon: I2.truck,
                      title:
                          S.t('No open dispatches', 'कोणतेही खुले डिस्पॅच नाहीत'),
                      subtitle: S.t('New delivery orders will appear here',
                          'नवीन डिलिव्हरी ऑर्डर येथे दिसतील'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        final code = '${row['do'] ?? ''}';
                        final ready = '${row['status']}' == 'ready';
                        return ready
                            ? _readyRow(code, _sub(row), () => _open(row))
                            : _row(code, _sub(row), () => _open(row));
                      },
                    ),
        ),
        _footer(),
      ],
    );
  }

  // ---- desktop layout (data table) ----

  Widget _desktop() {
    final rows = _data?.data ?? const <Json>[];
    final demo = _data?.demo ?? false;
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('DISPATCH', 'डिस्पॅच'),
          subtitle: S.t('${rows.length} open', '${rows.length} खुले'),
          onBack: nav.pop,
          demo: demo,
        ),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 1200,
            child: _data == null
                ? const SkeletonRows(count: 6)
                : rows.isEmpty
                    ? EmptyState2(
                        icon: I2.truck,
                        title: S.t(
                            'No open dispatches', 'कोणतेही खुले डिस्पॅच नाहीत'),
                        subtitle: S.t('New delivery orders will appear here',
                            'नवीन डिलिव्हरी ऑर्डर येथे दिसतील'),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: [_table(rows)],
                      ),
          ),
        ),
        _footer(),
      ],
    );
  }

  // Column widths shared by the desktop header + rows so the cells line up. A gap
  // is inserted between adjacent columns (see _gap) so the right-aligned status
  // pill never butts up against the expanded customer text.
  static const _wDo = 180.0;
  static const _wStatus = 130.0;
  static const _wChevron = 32.0;
  static const _gap = SizedBox(width: 16);

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
                SizedBox(width: _wDo, child: _th(S.t('DO', 'DO'))),
                _gap,
                Expanded(child: _th(S.t('Customer · detail', 'ग्राहक · तपशील'))),
                _gap,
                SizedBox(
                    width: _wStatus,
                    child: _th(S.t('Status', 'स्थिती'), right: true)),
                _gap,
                const SizedBox(width: _wChevron),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _tableRow(rows[i], i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _tableRow(Json row, bool last) {
    final code = '${row['do'] ?? ''}';
    final ready = '${row['status']}' == 'ready';
    return Pressable2(
      scale: 0.99,
      onTap: () => _open(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border:
              last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _wDo,
              child: Text(code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: F.mono(14, color: Y2.ink)),
            ),
            _gap,
            Expanded(
              child: Text(_sub(row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: F.hind(13, color: Y2.body)),
            ),
            _gap,
            SizedBox(
              width: _wStatus,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: ready
                      ? Pill2(
                          text: S.t('READY', 'तयार'),
                          fg: Y2.accent,
                          bg: const Color(0x141D4ED8),
                          borderColor: const Color(0x591D4ED8),
                        )
                      : Pill2(
                          text: S.t('OPEN', 'खुले'),
                          fg: Y2.body,
                          bg: Y2.lineSoft,
                          borderColor: Y2.line,
                          dot: false,
                        ),
                ),
              ),
            ),
            _gap,
            const SizedBox(
              width: _wChevron,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(I2.chevronRight, size: 18, color: Y2.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- shared footer ----

  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FB),
          border: Border(top: BorderSide(color: Y2.line)),
        ),
        child: PrimaryButton2(
          label: S.t('Start a dispatch', 'डिस्पॅच सुरू करा'),
          onTap: _startDispatch,
        ),
      );

  /// Start a new dispatch — seed the flow with the first READY order (or the
  /// first row) so the detail screen opens against a real DO, then navigate.
  void _startDispatch() {
    final rows = _data?.data ?? const <Json>[];
    Json? seed;
    for (final r in rows) {
      if ('${r['status']}' == 'ready') {
        seed = r;
        break;
      }
    }
    seed ??= rows.isNotEmpty ? rows.first : null;
    if (seed != null) {
      Ui2Flow.set('dispatch.do', seed['do']);
      Ui2Flow.set('dispatch.customer', seed['customer']);
    } else {
      Ui2Flow.set('dispatch.do', null);
      Ui2Flow.set('dispatch.customer', null);
    }
    nav.go(ScreenId.dispatchDetail);
  }

  Widget _readyRow(String code, String sub, VoidCallback onTap) => Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Y2.accent, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(code,
                              style: F.mono(14, color: Y2.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false),
                        ),
                        const SizedBox(width: 6),
                        Pill2(
                          text: S.t('READY', 'तयार'),
                          fg: Y2.accent,
                          bg: const Color(0x141D4ED8),
                          borderColor: const Color(0x591D4ED8),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(sub,
                          style: F.hind(12, color: Y2.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ),
        ),
      );

  Widget _row(String code, String sub, VoidCallback onTap) => Pressable2(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Y2.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Y2.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(code,
                        style: F.mono(14, color: Y2.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(sub,
                          style: F.hind(12, color: Y2.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(I2.chevronRight, size: 18, color: Y2.muted),
            ],
          ),
        ),
      );
}
