import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../data/api2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../validators.dart';
import '../widgets/bits.dart';
import '../widgets/polish2.dart';

/// Admin — Devices (office). Lists the registered station devices, registers a
/// new one, and deactivates one. Renders inside the responsive [OfficeShell] (so
/// no phone status bar / back affordance — the shell supplies the chrome).
///
/// Reads via [Data.stationDevices] (clearly-marked DEMO fallback when the
/// backend is unreachable or the table is empty). Writes go through the direct
/// admin endpoints: [Data.mutate] to create, [Data.patch] to deactivate.
class Ui2AdminDevicesScreen extends StatefulWidget {
  const Ui2AdminDevicesScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2AdminDevicesScreen> createState() => _Ui2AdminDevicesScreenState();
}

class _Ui2AdminDevicesScreenState extends State<Ui2AdminDevicesScreen> {
  // The four station kinds a device can be bound to.
  static const _stations = ['gate', 'qc', 'store', 'ppc'];

  Loaded<List<Json>>? _data;

  // List vs. inline add-device form.
  bool _adding = false;

  // Add-device form state.
  final _deviceKey = TextEditingController();
  final _label = TextEditingController();
  String? _station;
  bool _saving = false;

  // The id of the device whose Deactivate is mid-flight (so only it dims).
  int? _busyId;

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Register CTA + inline hints on every keystroke.
    for (final c in [_deviceKey, _label]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  // The device key must be a valid lowercase slug, the label a real (≥3-char,
  // contains a letter) string, and a station must be picked — so Register stays
  // hard-blocked until all three hold.
  bool get _keyValid => V.deviceKey(_deviceKey.text);
  bool get _labelValid => V.freeText(_label.text);
  bool get _canRegister => _keyValid && _labelValid && _station != null;

  @override
  void dispose() {
    _deviceKey.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await Data.stationDevices();
    if (!mounted) return;
    setState(() => _data = res);
  }

  void _openAdd() {
    setState(() {
      _deviceKey.clear();
      _label.clear();
      _station = null;
      _saving = false;
      _adding = true;
    });
  }

  void _cancelAdd() => setState(() => _adding = false);

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ------------------------------------------------------------- mutations ---

  Future<void> _register() async {
    final station = _station;
    // Hard-block: the disabled button already prevents this, but re-guard.
    if (_saving || !_canRegister || station == null) return;
    final key = _deviceKey.text.trim();
    final label = _label.text.trim();
    setState(() => _saving = true);
    final res = await Data.mutate('/master/station-devices', {
      'device_key': key,
      'station': station,
      'label': label,
    });
    if (!mounted) return;
    if (res.failed) {
      setState(() => _saving = false);
      _toast(res.error?.message ??
          S.t('Could not register device', 'उपकरण नोंदवता आले नाही'));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _saving = false;
      _adding = false;
    });
    _toast(S.t('Device registered', 'उपकरण नोंदवले'));
    await _load();
  }

  Future<void> _deactivate(Json d) async {
    final id = d['id'];
    if (_busyId != null || id is! int) return;
    setState(() => _busyId = id);
    final res =
        await Data.patch('/master/station-devices/$id', {'is_active': false});
    if (!mounted) return;
    if (res.failed) {
      setState(() => _busyId = null);
      _toast(res.error?.message ??
          S.t('Could not deactivate device', 'उपकरण निष्क्रिय करता आले नाही'));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _busyId = null);
    _toast(S.t('Device deactivated', 'उपकरण निष्क्रिय केले'));
    await _load();
  }

  // ----------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _phone(),
      tablet: (_) => _desktop(),
      desktop: (_) => _desktop(),
    );
  }

  // The Add CTA in the header (hidden while the add form is open). Shared by both
  // form factors.
  Widget? _addTrailing() => _adding
      ? null
      : Pressable2(
          onTap: _openAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: Y2.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 16, color: Colors.white),
                const SizedBox(width: 4),
                Text(S.t('Add', 'जोडा'),
                    style: F.hind(13, w: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        );

  Widget _emptyState() => EmptyState2(
        icon: Icons.devices_outlined,
        title: S.t('No devices yet', 'अद्याप उपकरणे नाहीत'),
        subtitle: S.t('Register a station device to get started.',
            'सुरू करण्यासाठी स्टेशन उपकरण नोंदवा.'),
        action: OutlineButton2(
          label: S.t('Add device', 'उपकरण जोडा'),
          onTap: _openAdd,
        ),
      );

  // ---- phone layout (vertical list of cards) ----

  Widget _phone() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('DEVICES', 'उपकरणे'),
          demo: loaded?.demo ?? false,
          trailing: _addTrailing(),
        ),
        Expanded(
          child: _adding
              ? _addForm()
              : loaded == null
                  ? const SkeletonRows(count: 4)
                  : rows.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                          itemCount: rows.length + 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 9),
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                    S.t('${rows.length} registered',
                                        '${rows.length} नोंदवलेले'),
                                    style: F.hind(12, color: Y2.muted)),
                              );
                            }
                            return _deviceCard(rows[i - 1]);
                          },
                        ),
        ),
      ],
    );
  }

  // ---- desktop layout (data table inside a capped content column) ----

  Widget _desktop() {
    final loaded = _data;
    final rows = loaded?.data ?? const <Json>[];
    return Column(
      children: [
        ScreenHeader2(
          title: S.t('DEVICES', 'उपकरणे'),
          demo: loaded?.demo ?? false,
          trailing: _addTrailing(),
        ),
        Expanded(
          child: ResponsiveContent(
            maxWidth: 1200,
            child: _adding
                ? _addForm()
                : loaded == null
                    ? const SkeletonRows(count: 6)
                    : rows.isEmpty
                        ? _emptyState()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      S.t('${rows.length} registered',
                                          '${rows.length} नोंदवलेले'),
                                      style: F.hind(12, color: Y2.muted)),
                                ),
                                _deviceTable(rows),
                              ],
                            ),
                          ),
          ),
        ),
      ],
    );
  }

  // Column widths shared by header + rows so the cells line up. A consistent gap
  // (see _gap) is inserted between EVERY pair of adjacent columns in both the
  // header and the data rows, so right-aligned values (the online word, the
  // "Last seen HH:mm" stamp) never butt up against the next column's text.
  // Sum of fixed widths + gaps + the Row's horizontal padding is kept well
  // ≤ 900px so a row can never overflow at the desktop content width; the
  // Expanded Device column absorbs the remainder.
  // 64 + 96 + 132 + 116 (fixed) + 5×16 (gaps) + 32 (padding) = 520.
  static const _wStatus = 64.0;
  static const _wStation = 96.0;
  static const _wSeen = 132.0;
  static const _wAction = 116.0;
  static const _gap = SizedBox(width: 16);

  Widget _deviceTable(List<Json> rows) {
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
                _th(_wStatus, S.t('Status', 'स्थिती')),
                _gap,
                Expanded(child: _th(null, S.t('Device', 'उपकरण'))),
                _gap,
                _th(_wStation, S.t('Station', 'स्टेशन')),
                _gap,
                _th(_wSeen, S.t('Last seen', 'शेवटचे'), right: true),
                _gap,
                _th(_wAction, ''),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _deviceRow(rows[i], i == rows.length - 1),
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
    // The Expanded primary-text column (w == null) ellipsises; every fixed
    // column shrinks its label via FittedBox so it can never overflow.
    if (w == null) return t;
    return SizedBox(
      width: w,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: t,
      ),
    );
  }

  Widget _deviceRow(Json d, bool last) {
    final label = '${d['label'] ?? S.t('Unnamed device', 'विनानाव उपकरण')}';
    final key = '${d['device_key'] ?? '—'}';
    final station = '${d['station'] ?? ''}';
    final online = _seenToday(d['last_seen_at']);
    final busy = _busyId == d['id'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border:
            last ? null : const Border(bottom: BorderSide(color: Y2.lineSoft)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Status dot + online/offline word.
          SizedBox(
            width: _wStatus,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(GlyphShape.dot, online ? Y2.green : Y2.muted2, size: 8),
                  const SizedBox(width: 7),
                  Text(
                      online
                          ? S.t('Online', 'ऑनलाइन')
                          : S.t('Offline', 'ऑफलाइन'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.hind(11,
                          w: FontWeight.w600,
                          color: online ? Y2.green : Y2.muted)),
                ],
              ),
            ),
          ),
          _gap,
          // Label + device key.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.hind(14, w: FontWeight.w600, color: Y2.ink)),
                const SizedBox(height: 1),
                Text(key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.mono(12, color: Y2.muted)),
              ],
            ),
          ),
          _gap,
          // Station pill.
          SizedBox(
            width: _wStation,
            child: station.isEmpty
                ? const SizedBox.shrink()
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Pill2(
                        text: station.toUpperCase(),
                        fg: Y2.accent,
                        bg: const Color(0x141D4ED8),
                        borderColor: const Color(0x331D4ED8),
                        dot: false),
                  ),
          ),
          _gap,
          // Last seen.
          SizedBox(
            width: _wSeen,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                  S.t('Last seen ${_lastSeen(d['last_seen_at'])}',
                      'शेवटचे ${_lastSeen(d['last_seen_at'])}'),
                  maxLines: 1,
                  style: F.hind(12, color: Y2.muted)),
            ),
          ),
          _gap,
          // Deactivate action.
          SizedBox(
            width: _wAction,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Pressable2(
                onTap: busy ? null : () => _deactivate(d),
                child: Opacity(
                  opacity: busy ? 0.5 : 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Y2.red),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(S.t('Deactivate', 'निष्क्रिय करा'),
                          style:
                              F.hind(13, w: FontWeight.w600, color: Y2.red)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ list cards ---

  Widget _deviceCard(Json d) {
    final label = '${d['label'] ?? S.t('Unnamed device', 'विनानाव उपकरण')}';
    final key = '${d['device_key'] ?? '—'}';
    final station = '${d['station'] ?? ''}';
    final online = _seenToday(d['last_seen_at']);
    final busy = _busyId == d['id'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Y2.card,
        borderRadius: BorderRadius.circular(Y2.rRow),
        border: Border.all(color: Y2.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 8),
                child: Glyph(GlyphShape.dot, online ? Y2.green : Y2.muted2,
                    size: 8),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: F.hind(14, w: FontWeight.w600, color: Y2.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(key,
                        style: F.mono(12, color: Y2.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (station.isNotEmpty) ...[
                const SizedBox(width: 8),
                Pill2(
                    text: station.toUpperCase(),
                    fg: Y2.accent,
                    bg: const Color(0x141D4ED8),
                    borderColor: const Color(0x331D4ED8),
                    dot: false),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                    S.t('Last seen ${_lastSeen(d['last_seen_at'])}',
                        'शेवटचे ${_lastSeen(d['last_seen_at'])}'),
                    style: F.hind(12, color: Y2.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Pressable2(
                onTap: busy ? null : () => _deactivate(d),
                child: Opacity(
                  opacity: busy ? 0.5 : 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Y2.red),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(S.t('Deactivate', 'निष्क्रिय करा'),
                          style:
                              F.hind(13, w: FontWeight.w600, color: Y2.red)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- add form ---

  Widget _addForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Text(S.t('Register a station device', 'स्टेशन उपकरण नोंदवा'),
            style: F.khand(17, ls: 0.2, color: Y2.ink)),
        const SizedBox(height: 14),
        _fieldLabel(S.t('Device key', 'डिव्हाइस की')),
        const SizedBox(height: 6),
        _textField(_deviceKey,
            hint: S.t('e.g. gate-kiosk-1', 'उदा. gate-kiosk-1'),
            mono: true,
            autofocus: true,
            formatters: V.slugInput),
        FieldHint(
          S.t('3–64 chars: a–z, 0–9, single hyphens',
              '3–64 अक्षरे: a–z, 0–9, एकल हायफन'),
          show: _deviceKey.text.trim().isNotEmpty && !_keyValid,
        ),
        const SizedBox(height: 14),
        _fieldLabel(S.t('Label', 'लेबल')),
        const SizedBox(height: 6),
        _textField(_label,
            hint: S.t('e.g. Gate scanner kiosk', 'उदा. गेट स्कॅनर कियोस्क')),
        FieldHint(
          S.t('At least 3 characters', 'किमान 3 अक्षरे'),
          show: _label.text.trim().isNotEmpty && !_labelValid,
        ),
        const SizedBox(height: 14),
        _fieldLabel(S.t('Station', 'स्टेशन')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _stations) _stationChip(s),
          ],
        ),
        const SizedBox(height: 22),
        PrimaryButton2(
          label: S.t('Register device', 'उपकरण नोंदवा'),
          busy: _saving,
          enabled: _canRegister,
          onTap: _register,
        ),
        const SizedBox(height: 10),
        OutlineButton2(
          label: S.t('Cancel', 'रद्द करा'),
          onTap: _saving ? null : _cancelAdd,
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) => Text(text,
      style: F.hind(12, w: FontWeight.w600, ls: 0.2, color: Y2.body));

  Widget _textField(TextEditingController c,
      {String? hint,
      bool mono = false,
      bool autofocus = false,
      List<TextInputFormatter>? formatters}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      inputFormatters: formatters,
      style: mono
          ? F.mono(14, color: Y2.ink)
          : F.hind(14, color: Y2.ink),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: F.hind(13, color: Y2.muted2),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Y2.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Y2.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Y2.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _stationChip(String s) {
    final selected = _station == s;
    return Pressable2(
      onTap: () => setState(() => _station = s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0x141D4ED8) : Y2.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: selected ? Y2.accent : Y2.line,
              width: selected ? 1.5 : 1),
        ),
        child: Text(s.toUpperCase(),
            style: F.hind(13,
                w: FontWeight.w600,
                ls: 0.3,
                color: selected ? Y2.accent : Y2.body)),
      ),
    );
  }

  // ------------------------------------------------------------- helpers ----

  /// Parse an ISO `last_seen_at` and return true when it falls on today's
  /// (local) calendar date — drives the online/offline dot.
  bool _seenToday(Object? raw) {
    final dt = _parse(raw);
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  /// "HH:mm" when parseable, otherwise an em-dash.
  String _lastSeen(Object? raw) {
    final dt = _parse(raw);
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  DateTime? _parse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
