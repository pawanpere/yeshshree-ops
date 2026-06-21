import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/icons2.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Production — Operations & WIP board (P-W).
///
/// A part runs through a sequence of operations (press → weld → assembly …). This
/// screen shows the routing as a pipeline with the quantity that has CLEARED each
/// operation, so the material sitting BETWEEN two stations (work-in-progress) is
/// visible at a glance. Tapping an operation records how many more pieces just
/// finished there (a mid-operation confirmation), advancing WIP one station —
/// exactly so the plant knows how much material is in WIP at any moment.
///
/// Phone: a vertical pipeline. Desktop: a horizontal pipeline + an operations
/// table with inline record buttons. Routing comes from SAP (demo-shaped here).
class Ui2ProdWipScreen extends ConsumerStatefulWidget {
  const Ui2ProdWipScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  ConsumerState<Ui2ProdWipScreen> createState() => _Ui2ProdWipScreenState();
}

class _Op {
  _Op(this.seq, this.name, this.wc, this.done);
  final int seq;
  final String name;
  final String wc;
  double done;
}

class _Part {
  _Part(this.materialId, this.material, this.line, this.plan, this.ops);
  final int materialId;
  final String material;
  final String line;
  final double plan;
  final List<_Op> ops;
}

class _Ui2ProdWipScreenState extends ConsumerState<Ui2ProdWipScreen> {
  List<_Part>? _parts;
  bool _demo = false;
  int _sel = 0;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Data.productionRoutings();
    if (!mounted) return;
    setState(() {
      _demo = res.demo;
      _parts = [
        for (final p in res.data)
          _Part(
            (p['material_id'] as num?)?.toInt() ?? 0,
            '${p['material'] ?? '—'}',
            '${p['line'] ?? '—'}',
            _num(p['plan']),
            [
              for (final o in (p['operations'] as List? ?? const []))
                _Op((o['seq'] as num?)?.toInt() ?? 0, '${o['name'] ?? '—'}',
                    '${o['wc'] ?? ''}', _num(o['done'])),
            ],
          ),
      ];
    });
  }

  static double _num(dynamic v) =>
      double.tryParse('$v'.replaceAll(',', '').trim()) ?? 0;

  _Part get _part => _parts![_sel.clamp(0, _parts!.length - 1)];

  /// WIP parked between operation [i] and the next one.
  double _wipAfter(int i) {
    final ops = _part.ops;
    if (i >= ops.length - 1) return 0;
    final d = ops[i].done - ops[i + 1].done;
    return d < 0 ? 0 : d;
  }

  double get _totalWip {
    var s = 0.0;
    for (var i = 0; i < _part.ops.length - 1; i++) {
      s += _wipAfter(i);
    }
    return s;
  }

  double get _fg => _part.ops.isEmpty ? 0 : _part.ops.last.done;

  /// Max additional pieces that can be recorded at operation [i]: the available
  /// WIP that has reached the previous station (or the plan, for the first op).
  double _maxAddFor(int i) {
    final ops = _part.ops;
    final cap = i == 0 ? _part.plan - ops[0].done : ops[i - 1].done - ops[i].done;
    return cap < 0 ? 0 : cap;
  }

  String _fmt(double v) {
    if (v != v.roundToDouble()) return v.toStringAsFixed(0);
    final s = v.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String get _unit => S.t('pcs', 'नग');

  void _pickPart() {
    final parts = _parts ?? const <_Part>[];
    nav.overlay(Picker2Sheet<int>(
      title: S.t('Select part', 'भाग निवडा'),
      options: [
        for (var i = 0; i < parts.length; i++)
          Picker2Option<int>(parts[i].material, i,
              sub: '${parts[i].line} · ${S.t('plan', 'योजना')} ${_fmt(parts[i].plan)}'),
      ],
      onPick: (i) {
        setState(() => _sel = i);
        nav.hideOverlay();
      },
    ));
  }

  void _openRecord(int i) {
    final op = _part.ops[i];
    nav.overlay(_OpRecordSheet(
      opName: op.name,
      unit: _unit,
      available: _maxAddFor(i),
      onCancel: nav.hideOverlay,
      onPost: (good, reject) async {
        nav.hideOverlay();
        await _record(i, good, reject);
      },
    ));
  }

  Future<void> _record(int i, double good, double reject) async {
    final op = _part.ops[i];
    final add = good > _maxAddFor(i) ? _maxAddFor(i) : good;
    await Data.submitOperationConfirmation(ref, {
      'line_id': 1,
      'material_id': _part.materialId,
      'operation_seq': op.seq,
      'operation_name': op.name,
      'good_qty': '$good',
      'rejected_qty': '$reject',
      'kind': 'operation',
    });
    if (!mounted) return;
    setState(() => op.done = op.done + add);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Y2.green,
      content: Text(
          S.t('Recorded ${_fmt(add)} $_unit after ${op.name}',
              '${op.name} नंतर ${_fmt(add)} $_unit नोंदवले'),
          style: F.hind(13, color: Colors.white)),
    ));
  }

  // ---------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    if (_parts == null) {
      return Column(children: const [
        StatusBar2(),
        Expanded(child: SkeletonRows(count: 5)),
      ]);
    }
    return Responsive(
      phone: (_) => _scaffold(child: _phoneBody(), phoneChrome: true),
      tablet: (_) => _scaffold(child: _desktopBody(), phoneChrome: false),
      desktop: (_) => _scaffold(child: _desktopBody(), phoneChrome: false),
    );
  }

  Widget _scaffold({required Widget child, required bool phoneChrome}) {
    return Column(
      children: [
        if (phoneChrome) const StatusBar2(),
        ScreenHeader2(
          title: S.t('OPERATIONS · WIP', 'ऑपरेशन्स · WIP'),
          subtitle: '${_part.material} · ${_part.line}',
          onBack: nav.pop,
          demo: _demo,
        ),
        Expanded(child: child),
      ],
    );
  }

  // ---- shared header pieces ----

  Widget _partSelector() => Pressable2(
        onTap: _pickPart,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Y2.card,
            border: Border.all(color: Y2.line),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              const Icon(I2.factory, size: 18, color: Y2.muted),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('PART', 'भाग'),
                        style: F.hind(10,
                            w: FontWeight.w600, ls: 0.5, color: Y2.muted)),
                    Text(_part.material,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.hind(15, w: FontWeight.w600, color: Y2.ink)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(S.t('Change', 'बदला'),
                  style: F.hind(12, w: FontWeight.w600, color: Y2.accent)),
              const Icon(I2.chevronRight, size: 16, color: Y2.accent),
            ],
          ),
        ),
      );

  Widget _summary({required bool wide}) {
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: F.hind(10,
                      w: FontWeight.w600, ls: 0.4, color: Y2.muted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: F.mono(20, w: FontWeight.w700, color: color)),
              ),
            ],
          ),
        );
    return Card2(
      padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 13, vertical: 13),
      child: Row(
        children: [
          stat(S.t('PLAN', 'योजना'), _fmt(_part.plan), Y2.ink),
          _divider(),
          stat(S.t('IN WIP', 'WIP मध्ये'), _fmt(_totalWip), Y2.orange),
          _divider(),
          stat(S.t('FINISHED', 'पूर्ण'), _fmt(_fg), Y2.green),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1, height: 34, color: Y2.line, margin: const EdgeInsets.symmetric(horizontal: 12));

  Widget _seqBadge(int seq, {Color? color}) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (color ?? Y2.accent).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: (color ?? Y2.accent).withValues(alpha: 0.30)),
        ),
        child: Text('$seq',
            style: F.mono(13, w: FontWeight.w700, color: color ?? Y2.accent)),
      );

  Widget _recordBtn(int i) {
    final full = _maxAddFor(i) <= 0;
    return Pressable2(
      scale: 0.96,
      onTap: full ? null : () => _openRecord(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: full ? Y2.lineSoft : Y2.accent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(full ? I2.check : I2.edit,
                size: 14, color: full ? Y2.muted : Colors.white),
            const SizedBox(width: 6),
            Text(full ? S.t('Done', 'पूर्ण') : S.t('Record', 'नोंदवा'),
                style: F.hind(12,
                    w: FontWeight.w700, color: full ? Y2.muted : Colors.white)),
          ],
        ),
      ),
    );
  }

  // ---- phone layout (vertical pipeline) ----

  Widget _phoneBody() {
    final ops = _part.ops;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _partSelector(),
          const SizedBox(height: 11),
          _summary(wide: false),
          const SizedBox(height: 14),
          // RM feed marker.
          _endNode(S.t('Raw material in', 'कच्चा माल आत'),
              _fmt(ops.isEmpty ? 0 : ops.first.done), Y2.muted, I2.store),
          for (var i = 0; i < ops.length; i++) ...[
            _wipConnector(i == 0 ? null : _wipAfter(i - 1)),
            _opNode(i),
          ],
          _wipConnector(null, toFg: true),
          _endNode(S.t('Finished goods', 'तयार माल'), _fmt(_fg), Y2.green, I2.check),
        ],
      ),
    );
  }

  Widget _opNode(int i) {
    final op = _part.ops[i];
    final done = _maxAddFor(i) <= 0;
    return Card2(
      leftBorder: done ? Y2.green : Y2.accent,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          _seqBadge(op.seq, color: done ? Y2.green : Y2.accent),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(op.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(15, w: FontWeight.w700, color: Y2.ink)),
                Text(op.wc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(11, color: Y2.muted)),
                const SizedBox(height: 4),
                Text(S.t('${_fmt(op.done)} $_unit cleared', '${_fmt(op.done)} $_unit पूर्ण'),
                    style: F.mono(12, w: FontWeight.w600, color: Y2.body)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _recordBtn(i),
        ],
      ),
    );
  }

  /// Connector between two op nodes showing the WIP parked there. [wip] null on
  /// the very first connector (RM→op1, no parked WIP) unless [toFg].
  Widget _wipConnector(double? wip, {bool toFg = false}) {
    final show = wip != null && wip > 0;
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Row(
        children: [
          Container(width: 2, height: 26, color: Y2.line),
          const SizedBox(width: 12),
          if (show)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Y2.orangeTint,
                border: Border.all(color: Y2.orangeLine),
                borderRadius: BorderRadius.circular(Y2.rPill),
              ),
              child: Text(
                  S.t('WIP  ${_fmt(wip)} $_unit', 'WIP  ${_fmt(wip)} $_unit'),
                  style: F.hind(11, w: FontWeight.w700, color: Y2.orange)),
            )
          else
            Text(toFg ? S.t('to finished goods', 'तयार मालाकडे') : S.t('flowing', 'वाहत आहे'),
                style: F.hind(11, color: Y2.muted2)),
        ],
      ),
    );
  }

  Widget _endNode(String label, String qty, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: F.hind(13, w: FontWeight.w700, color: Y2.ink))),
            Text('$qty $_unit',
                style: F.mono(13, w: FontWeight.w700, color: color)),
          ],
        ),
      );

  // ---- desktop layout (horizontal pipeline + table) ----

  Widget _desktopBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: _partSelector()),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _summary(wide: true)),
            ],
          ),
          const SizedBox(height: 16),
          _horizontalPipeline(),
          const SizedBox(height: 16),
          _opTable(),
        ],
      ),
    );
  }

  Widget _horizontalPipeline() {
    final ops = _part.ops;
    final nodes = <Widget>[];
    nodes.add(_flowChip(
        S.t('RM in', 'RM आत'), _fmt(ops.isEmpty ? 0 : ops.first.done), Y2.muted));
    for (var i = 0; i < ops.length; i++) {
      nodes.add(_arrow(i == 0 ? 0 : _wipAfter(i - 1)));
      nodes.add(_pipelineNode(i));
    }
    nodes.add(_arrow(0, toFg: true));
    nodes.add(_flowChip(S.t('FG', 'FG'), _fmt(_fg), Y2.green));
    return Card2(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: nodes),
      ),
    );
  }

  Widget _pipelineNode(int i) {
    final op = _part.ops[i];
    final done = _maxAddFor(i) <= 0;
    final color = done ? Y2.green : Y2.accent;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _seqBadge(op.seq, color: color),
              const Spacer(),
              Text('${_fmt(op.done)} $_unit',
                  style: F.mono(12, w: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 9),
          Text(op.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.hind(14, w: FontWeight.w700, color: Y2.ink)),
          Text(op.wc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.hind(11, color: Y2.muted)),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: _recordBtn(i)),
        ],
      ),
    );
  }

  /// Arrow between two pipeline nodes, with a WIP chip above when material is
  /// parked there.
  Widget _arrow(double wip, {bool toFg = false}) {
    final show = wip > 0;
    return SizedBox(
      width: 86,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (show)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Y2.orangeTint,
                border: Border.all(color: Y2.orangeLine),
                borderRadius: BorderRadius.circular(Y2.rPill),
              ),
              child: Text('WIP ${_fmt(wip)}',
                  style: F.hind(10, w: FontWeight.w700, color: Y2.orange)),
            )
          else
            Text(toFg ? S.t('ship', 'पाठवा') : '·',
                style: F.hind(10, color: Y2.muted2)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 44, height: 2, color: show ? Y2.orangeLine : Y2.line),
              Icon(I2.chevronRight,
                  size: 16, color: show ? Y2.orange : Y2.muted2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flowChip(String label, String qty, Color color) => Container(
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Text(label,
                style: F.hind(11, w: FontWeight.w700, color: Y2.ink)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$qty $_unit',
                  style: F.mono(13, w: FontWeight.w700, color: color)),
            ),
          ],
        ),
      );

  Widget _opTable() {
    final ops = _part.ops;
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8FB),
              border: Border(bottom: BorderSide(color: Y2.line)),
            ),
            child: Row(
              children: [
                SizedBox(width: 44, child: _th('OP')),
                Expanded(child: _th(S.t('Operation', 'ऑपरेशन'))),
                Expanded(child: _th(S.t('Work centre', 'वर्क सेंटर'))),
                SizedBox(width: 110, child: _th(S.t('Cleared', 'पूर्ण'), right: true)),
                SizedBox(width: 110, child: _th(S.t('WIP after', 'पुढे WIP'), right: true)),
                const SizedBox(width: 16),
                const SizedBox(width: 120),
              ],
            ),
          ),
          for (var i = 0; i < ops.length; i++) _opRow(i),
        ],
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Text(s,
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: F.hind(11, w: FontWeight.w600, ls: 0.3, color: Y2.muted));

  Widget _opRow(int i) {
    final op = _part.ops[i];
    final wip = _wipAfter(i);
    final last = i == _part.ops.length - 1;
    final done = _maxAddFor(i) <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        children: [
          SizedBox(width: 44, child: _seqBadge(op.seq, color: done ? Y2.green : Y2.accent)),
          Expanded(
            child: Text(op.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.hind(13, w: FontWeight.w700, color: Y2.ink)),
          ),
          Expanded(
            child: Text(op.wc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.hind(12, color: Y2.muted)),
          ),
          SizedBox(
            width: 110,
            child: Text('${_fmt(op.done)} $_unit',
                textAlign: TextAlign.right,
                style: F.mono(12, w: FontWeight.w600, color: Y2.ink)),
          ),
          SizedBox(
            width: 110,
            child: Text(last ? '—' : '${_fmt(wip)} $_unit',
                textAlign: TextAlign.right,
                style: F.mono(12,
                    w: FontWeight.w700,
                    color: (!last && wip > 0) ? Y2.orange : Y2.muted)),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 120, child: Align(alignment: Alignment.centerRight, child: _recordBtn(i))),
        ],
      ),
    );
  }
}

/// Bottom sheet to record completion AFTER one operation (the mid-operation
/// confirmation). Posts good + reject; the parent advances WIP one station.
class _OpRecordSheet extends StatefulWidget {
  const _OpRecordSheet({
    required this.opName,
    required this.unit,
    required this.available,
    required this.onPost,
    required this.onCancel,
  });
  final String opName;
  final String unit;
  final double available;
  final void Function(double good, double reject) onPost;
  final VoidCallback onCancel;

  @override
  State<_OpRecordSheet> createState() => _OpRecordSheetState();
}

class _OpRecordSheetState extends State<_OpRecordSheet> {
  double _good = 0;
  double _reject = 0;

  void _addGood(double n) =>
      setState(() => _good = (_good + n).clamp(0, widget.available));
  void _addReject(double n) => setState(() => _reject = (_reject + n).clamp(0, 9999));

  @override
  Widget build(BuildContext context) {
    final cap = widget.available;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Y2.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(S.t('Record after ${widget.opName}', '${widget.opName} नंतर नोंदवा'),
              style: F.khand(18, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 2),
          Text(
              S.t('${_fmt(cap)} ${widget.unit} waiting before this operation',
                  'या ऑपरेशनपूर्वी ${_fmt(cap)} ${widget.unit} प्रतीक्षेत'),
              style: F.hind(12, color: Y2.muted)),
          const SizedBox(height: 16),
          _counter(
            label: S.t('COMPLETED', 'पूर्ण झाले'),
            value: _good,
            color: Y2.green,
            onMinus: () => _addGood(-1),
            onPlus: () => _addGood(1),
            quick: _addGood,
          ),
          const SizedBox(height: 12),
          _counter(
            label: S.t('REJECTED', 'नाकारले'),
            value: _reject,
            color: _reject > 0 ? Y2.red : Y2.ink,
            onMinus: () => _addReject(-1),
            onPlus: () => _addReject(1),
            quick: _addReject,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlineButton2(
                    label: S.t('Cancel', 'रद्द'), onTap: widget.onCancel),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PrimaryButton2(
                  label: S.t('Post completion', 'पूर्तता नोंदवा'),
                  enabled: _good > 0 && _reject <= _good + cap,
                  onTap: () => widget.onPost(_good, _reject),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    final s = v.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _counter({
    required String label,
    required double value,
    required Color color,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required void Function(double) quick,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        border: Border.all(color: Y2.line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: F.hind(11, w: FontWeight.w600, ls: 0.6, color: Y2.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              _step('−', onMinus),
              Expanded(
                child: Center(
                  child: Text(_fmt(value),
                      style: F.mono(36, height: 1, color: color)),
                ),
              ),
              _step('+', onPlus),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _quick('+5', () => quick(5)),
              const SizedBox(width: 8),
              _quick('+10', () => quick(10)),
              const SizedBox(width: 8),
              _quick('+25', () => quick(25)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(String g, VoidCallback onTap) => Pressable2(
        scale: 0.92,
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD2DAE6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(g, style: F.khand(26, w: FontWeight.w400, color: Y2.ink)),
        ),
      );

  Widget _quick(String label, VoidCallback onTap) => Expanded(
        child: Pressable2(
          scale: 0.94,
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              border: Border.all(color: Y2.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
          ),
        ),
      );
}
