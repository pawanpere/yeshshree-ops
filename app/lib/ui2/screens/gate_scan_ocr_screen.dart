import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../data/ocr2.dart';
import '../nav.dart';
import '../responsive.dart';
import '../tokens.dart';
import '../widgets/bits.dart';
import '../widgets/frame.dart';
import '../widgets/picker2.dart';
import '../widgets/polish2.dart';

/// Gate — LIVE OCR scan. The "scanner front door" for the gate role: a scanned
/// invoice (ScanJet scan-to-folder, polled via [Ocr.latest]) — or a bundled
/// sample invoice — is OCR'd by Google Vision on the demo OCR service, matched to
/// a (dummy) open PO, and its material is PINNED from the PO. The operator enters
/// the physically-counted qty + QC result, and a SAP-ready GRN Excel is generated
/// and downloaded. Mirrors the standalone demo (`yeshshree-ops/demo/server.py`)
/// but in the ui2 design system.
///
/// The OCR service is a separate tokenless helper (`demo/api.py`, default :8900);
/// when it is unreachable this screen says so plainly instead of failing.
class Ui2GateScanOcrScreen extends StatefulWidget {
  const Ui2GateScanOcrScreen({super.key, required this.nav});
  final PhoneNav nav;

  @override
  State<Ui2GateScanOcrScreen> createState() => _Ui2GateScanOcrScreenState();
}

enum _Stage { waiting, review, done }

class _Ui2GateScanOcrScreenState extends State<Ui2GateScanOcrScreen> {
  _Stage _stage = _Stage.waiting;
  Timer? _poll;
  int _seenId = 0;

  bool? _serviceUp; // null = still checking
  bool _hasKey = false;
  List<Json> _samples = const [];

  Json? _entry; // {id, matched, po, fields, error, ocr_mode, image_b64}
  String? _banner; // transient inline error/info (no Scaffold for SnackBars)
  bool _busy = false;
  String? _gateEntryNo; // generated when the arrival is acknowledged

  PhoneNav get nav => widget.nav;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------- service ---

  Future<void> _check() async {
    final h = await Ocr.health();
    final pos = h == null ? const <Json>[] : await Ocr.pos();
    if (!mounted) return;
    setState(() {
      _serviceUp = h != null;
      _hasKey = h?['has_key'] == true;
      _samples = pos;
    });
  }

  Future<void> _pollOnce() async {
    if (_stage != _Stage.waiting) return;
    final p = await Ocr.latest(after: _seenId);
    if (!mounted) return;
    if (p == null) {
      if (_serviceUp != false) setState(() => _serviceUp = false);
      return;
    }
    if (_serviceUp != true) setState(() => _serviceUp = true);
    if (p.entry != null) _onDecoded(p.entry!);
  }

  Future<void> _useSample(String poNo) async {
    setState(() {
      _busy = true;
      _banner = null;
    });
    final e = await Ocr.ingestSample(poNo);
    if (!mounted) return;
    setState(() => _busy = false);
    if (e == null) {
      setState(() {
        _serviceUp = false;
        _banner = S.t('OCR service offline — start it on :8900.',
            'OCR सेवा बंद — :8900 वर सुरू करा.');
      });
      return;
    }
    _onDecoded(e);
  }

  void _onDecoded(Json e) {
    _seenId = (e['id'] as num?)?.toInt() ?? _seenId;
    setState(() {
      _entry = e;
      _banner = e['error'] as String?;
      _stage = _Stage.review;
    });
  }

  Future<void> _pickPoManually() async {
    final pos = _samples.isNotEmpty ? _samples : await Ocr.pos();
    if (!mounted) return;
    _samples = pos;
    nav.overlay(Picker2Sheet<String>(
      title: S.t('Pick the purchase order', 'खरेदी ऑर्डर निवडा'),
      options: [
        for (final p in pos)
          Picker2Option<String>(
            'PO ${p['po_no']}',
            '${p['po_no']}',
            sub: '${p['vendor_name'] ?? '—'} · ${p['material_desc'] ?? '—'}',
          ),
      ],
      onPick: (poNo) {
        final p = pos.firstWhere((r) => '${r['po_no']}' == poNo,
            orElse: () => const {});
        // Promote the manual pick to the matched PO. The dummy /ocr/pos rows carry
        // enough to pin material + drive the GRN (po_no/line/material/uom/qty…).
        setState(() {
          final entry = _entry ?? <String, dynamic>{};
          entry['po'] = p;
          entry['matched'] = p.isNotEmpty;
          _entry = entry;
          _banner = null;
        });
        nav.hideOverlay();
      },
    ));
  }

  /// The gate only ACKNOWLEDGES the arrival and generates its gate-entry number —
  /// it does NOT run QC or a GRN. EVERY invoice goes through, even with no PO
  /// matched: Stores counts it in (GRN), then Quality does the QC. The receipt
  /// itself happens on the Receiving screen.
  void _sendToGrn() {
    // A fresh gate-entry number for this acknowledgement (demo: time-derived).
    final n = DateTime.now().millisecondsSinceEpoch.remainder(90000) + 10000;
    setState(() {
      _gateEntryNo = 'GE-$n';
      _banner = null;
      _stage = _Stage.done;
    });
  }

  void _nextScan() {
    setState(() {
      _entry = null;
      _banner = null;
      _gateEntryNo = null;
      _stage = _Stage.waiting;
    });
  }

  // -------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return Responsive(
      phone: (_) => _scaffold(_phoneBody(), wide: false),
      tablet: (_) => _scaffold(_wideBody(), wide: true),
      desktop: (_) => _scaffold(_wideBody(), wide: true),
    );
  }

  Widget _header() => ScreenHeader2(
        title: S.t('GATE — SCAN', 'गेट — स्कॅन'),
        subtitle: S.t('live OCR · PO match', 'लाइव्ह OCR · PO जुळवणी'),
        onBack: nav.pop,
        trailing: _ocrPill(),
      );

  Widget _ocrPill() {
    final up = _serviceUp;
    if (up == null) {
      return Pill2(
          text: S.t('CHECKING', 'तपासत'),
          fg: Y2.muted,
          bg: Y2.lineSoft,
          borderColor: Y2.line);
    }
    if (!up) {
      return Pill2(
          text: S.t('OCR OFFLINE', 'OCR बंद'),
          fg: Y2.red,
          bg: Y2.redTint,
          borderColor: Y2.redLine);
    }
    return _hasKey
        ? Pill2(
            text: S.t('OCR LIVE', 'OCR सुरू'),
            fg: Y2.green,
            bg: Y2.greenTint,
            borderColor: Y2.greenLine)
        : Pill2(
            text: S.t('SAMPLE ONLY', 'फक्त नमुना'),
            fg: Y2.orange,
            bg: Y2.orangeTint,
            borderColor: Y2.orangeLine);
  }

  Widget _scaffold(Widget body, {required bool wide}) {
    final content = Column(
      children: [
        if (!wide) const StatusBar2(),
        _header(),
        Expanded(child: body),
        _footer(wide),
      ],
    );
    return content;
  }

  Widget _phoneBody() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _stageCards(),
        ),
      );

  Widget _wideBody() => ResponsiveContent(
        maxWidth: _stage == _Stage.review ? 1040 : 760,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: _stage == _Stage.review
              ? _reviewWide()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _stageCards(),
                ),
        ),
      );

  List<Widget> _stageCards() {
    switch (_stage) {
      case _Stage.waiting:
        return _waitingCards();
      case _Stage.review:
        return _reviewCards();
      case _Stage.done:
        return _doneCards();
    }
  }

  // ---- WAITING ----

  List<Widget> _waitingCards() {
    final offline = _serviceUp == false;
    return [
      if (_banner != null) ...[_bannerBox(_banner!), const SizedBox(height: 11)],
      Card2(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
        child: Column(
          children: [
            const Icon(Icons.document_scanner_outlined, size: 40, color: Y2.accent),
            const SizedBox(height: 12),
            Text(S.t('Waiting for a scan…', 'स्कॅनची प्रतीक्षा…'),
                style: F.khand(20, color: Y2.ink)),
            const SizedBox(height: 6),
            Text(
              S.t(
                  'Scan an invoice at the gate — it drops into the watch folder, '
                      'is read by OCR, and opens here automatically.',
                  'गेटवर इनव्हॉइस स्कॅन करा — ते वॉच फोल्डरमध्ये येते, OCR वाचतो '
                      'आणि इथे आपोआप उघडते.'),
              textAlign: TextAlign.center,
              style: F.hind(12, color: Y2.muted, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (offline)
        _bannerBox(S.t(
            'OCR service not reachable. Start it:  cd demo  ·  uvicorn api:app --port 8900',
            'OCR सेवा उपलब्ध नाही. सुरू करा:  cd demo  ·  uvicorn api:app --port 8900'))
      else ...[
        Row(children: [
          Expanded(
              child: Text(
                  S.t('No scanner handy? OCR a sample invoice:',
                      'स्कॅनर नाही? नमुना इनव्हॉइस OCR करा:'),
                  style: F.hind(12, w: FontWeight.w600, color: Y2.body))),
        ]),
        const SizedBox(height: 9),
        ..._sampleButtons(),
      ],
    ];
  }

  List<Widget> _sampleButtons() {
    final rows = _samples.isNotEmpty
        ? _samples
        : const [
            {'po_no': '4500100231', 'vendor_name': 'Sentry Steel & Metals'},
            {'po_no': '4500100232', 'vendor_name': 'Apex Metalloys'},
            {'po_no': '4500100233', 'vendor_name': 'Shree Balaji Steel'},
          ];
    return [
      for (final p in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Card2(
            onTap: _busy ? null : () => _useSample('${p['po_no']}'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined,
                    size: 18, color: Y2.accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PO ${p['po_no']}',
                          style: F.mono(13, w: FontWeight.w600, color: Y2.ink)),
                      const SizedBox(height: 2),
                      Text('${p['vendor_name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.hind(11, color: Y2.muted)),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Text(S.t('Scan ▸', 'स्कॅन ▸'),
                      style: F.hind(12, w: FontWeight.w700, color: Y2.accent)),
              ],
            ),
          ),
        ),
    ];
  }

  // ---- REVIEW ----

  List<Widget> _reviewCards() {
    final matched = _entry?['po'] is Map;
    return [
      if (_banner != null) ...[_bannerBox(_banner!), const SizedBox(height: 11)],
      matched ? _matchBanner() : _noMatchBanner(),
      const SizedBox(height: 11),
      _imageCard(),
      const SizedBox(height: 11),
      if (matched)
        _poCard()
      else
        _pickCard(),
    ];
  }

  /// Desktop: scanned page on the left, decode + QC on the right.
  Widget _reviewWide() {
    final matched = _entry?['po'] is Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_banner != null) ...[_bannerBox(_banner!), const SizedBox(height: 12)],
        matched ? _matchBanner() : _noMatchBanner(),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _imageCard()),
              const SizedBox(width: 16),
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: matched ? [_poCard()] : [_pickCard()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _matchBanner() {
    final po = _entry!['po'] as Map;
    return _statusBanner(
      Y2.green,
      Y2.greenTint,
      const Color(0xFFA8DEC4),
      S.t('PO matched · ${po['po_no']} / line ${po['line'] ?? '—'}',
          'PO जुळले · ${po['po_no']} / ओळ ${po['line'] ?? '—'}'),
    );
  }

  Widget _noMatchBanner() {
    final cands = ((_entry?['fields'] as Map?)?['po_candidates'] as List?) ?? const [];
    final read = cands.isEmpty ? '—' : cands.join(', ');
    return _statusBanner(
      Y2.orange,
      Y2.orangeTint,
      Y2.orangeLine,
      S.t('No PO auto-matched · OCR read $read',
          'PO आपोआप जुळले नाही · OCR ने वाचले $read'),
    );
  }

  Widget _imageCard() {
    final b64 = '${_entry?['image_b64'] ?? ''}';
    final mode = '${_entry?['ocr_mode'] ?? ''}';
    Widget img;
    if (b64.isEmpty) {
      img = Container(
        height: 220,
        alignment: Alignment.center,
        color: Y2.lineSoft,
        child: Text(S.t('no image', 'प्रतिमा नाही'),
            style: F.hind(12, color: Y2.muted)),
      );
    } else {
      img = Image.memory(base64Decode(b64),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox(height: 200));
    }
    return Card2(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF11243F),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 14, color: Colors.white),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(S.t('Scanned invoice', 'स्कॅन केलेले इनव्हॉइस'),
                      style: F.hind(11, w: FontWeight.w600, color: Colors.white)),
                ),
                if (mode == 'skipped_no_key')
                  Text(S.t('OCR skipped · no key', 'OCR वगळले · की नाही'),
                      style: F.hind(10, color: const Color(0xFFE6B800))),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: img,
          ),
        ],
      ),
    );
  }

  Widget _poCard() {
    final po = _entry!['po'] as Map;
    final fields = (_entry?['fields'] as Map?) ?? const {};
    final lookalikes = (po['lookalikes'] as List?) ?? const [];
    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('MATERIAL PINNED BY PO', 'PO ने निश्चित केलेला माल'),
              style: F.hind(10, w: FontWeight.w700, ls: 0.4, color: Y2.muted)),
          const SizedBox(height: 8),
          Text('${po['material_code'] ?? ''}',
              style: F.mono(15, w: FontWeight.w700, color: Y2.ink)),
          const SizedBox(height: 2),
          Text('${po['material_desc'] ?? ''}',
              style: F.hind(13, color: Y2.body, height: 1.3)),
          const SizedBox(height: 12),
          _kv(S.t('Vendor', 'पुरवठादार'), '${po['vendor_name'] ?? '—'}'),
          _kv(S.t('OCR — GSTIN', 'OCR — GSTIN'),
              '${fields['vendor_gstin'] ?? '—'}'),
          _kv(S.t('OCR — Invoice', 'OCR — इनव्हॉइस'),
              '${fields['invoice_no'] ?? '—'}'),
          _kv(S.t('Grade / UOM', 'ग्रेड / UOM'),
              '${po['grade'] ?? '—'} · ${po['uom'] ?? ''}'),
          _kv(S.t('PO open qty', 'PO शिल्लक'),
              '${po['open_qty'] ?? '—'} ${po['uom'] ?? ''}'),
          if (lookalikes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(S.t('Ruled out (look-alikes)', 'वगळले (सारखे दिसणारे)'),
                style: F.hind(10, w: FontWeight.w700, ls: 0.4, color: Y2.muted)),
            const SizedBox(height: 5),
            for (final x in lookalikes)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        margin: const EdgeInsets.only(top: 3, right: 8),
                        width: 3,
                        height: 13,
                        color: Y2.redLine),
                    Expanded(
                        child: Text('$x',
                            style: F.hind(11, color: Y2.muted, height: 1.3))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pickCard() {
    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.t('OCR could not pin a PO', 'OCR ला PO निश्चित करता आले नाही'),
              style: F.hind(13, w: FontWeight.w600, color: Y2.ink)),
          const SizedBox(height: 4),
          Text(
              S.t('Pick the purchase order manually — the demo never stalls.',
                  'खरेदी ऑर्डर स्वतः निवडा — डेमो कधीच थांबत नाही.'),
              style: F.hind(11, color: Y2.muted)),
          const SizedBox(height: 12),
          PrimaryButton2(
              label: S.t('Pick a PO manually', 'PO स्वतः निवडा'),
              onTap: _pickPoManually),
        ],
      ),
    );
  }

  // ---- DONE ----

  List<Widget> _doneCards() {
    final po = _entry?['po'] as Map?;
    final fields = (_entry?['fields'] as Map?) ?? const {};
    final matched = po != null;
    return [
      Card2(
        leftBorder: Y2.green,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.check_circle, size: 20, color: Y2.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(S.t('Gate entry created', 'गेट नोंद तयार'),
                    style: F.khand(18, color: Y2.ink)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
                S.t('Arrival logged & sent to GRN. Stores counts it in, then '
                    'Quality does the QC — on the Receiving screen.',
                    'आवक नोंदवली व GRN कडे पाठवली. स्टोअर मोजते, मग गुणवत्ता QC करते '
                    '— Receiving स्क्रीनवर.'),
                style: F.hind(11, color: Y2.muted)),
            const SizedBox(height: 12),
            // The gate-entry number that now follows this load everywhere.
            _kv(S.t('Gate entry no.', 'गेट नोंद क्र.'), _gateEntryNo ?? '—'),
            _kv(S.t('PO / line', 'PO / ओळ'),
                matched ? '${po['po_no']} / ${po['line'] ?? '—'}' : S.t('No PO matched — flagged', 'PO जुळले नाही — फ्लॅग')),
            _kv(S.t('Material', 'माल'),
                matched ? '${po['material_code'] ?? '—'}' : '—'),
            _kv(S.t('Vendor', 'पुरवठादार'),
                matched ? '${po['vendor_name'] ?? '—'}' : '—'),
            _kv(S.t('OCR — Invoice', 'OCR — इनव्हॉइस'),
                '${fields['invoice_no'] ?? '—'}'),
          ],
        ),
      ),
    ];
  }

  // ---- footer (action bar per stage) ----

  Widget _footer(bool wide) {
    Widget? action;
    switch (_stage) {
      case _Stage.waiting:
        return const SizedBox.shrink();
      case _Stage.review:
        // Every invoice goes through — even with no PO matched — so the button is
        // always available once a scan is on screen.
        action = PrimaryButton2(
          label: S.t('Send to GRN', 'GRN कडे पाठवा'),
          onTap: _sendToGrn,
        );
      case _Stage.done:
        action = OutlineButton2(
            label: S.t('Scan next', 'पुढील स्कॅन'), onTap: _nextScan);
    }
    final bar = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FB),
        border: Border(top: BorderSide(color: Y2.line)),
      ),
      child: action,
    );
    return wide ? ResponsiveContent(maxWidth: 1040, child: bar) : bar;
  }

  // ---- small shared pieces ----

  Widget _statusBanner(Color fg, Color bg, Color border, String text) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(text, style: F.hind(13, w: FontWeight.w600, color: fg))),
        ]),
      );

  Widget _bannerBox(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Y2.redTint,
          border: Border.all(color: Y2.redLine),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: F.hind(12, w: FontWeight.w600, color: Y2.red)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: F.hind(12, color: Y2.muted)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: F.mono(12, w: FontWeight.w600, color: Y2.ink)),
            ),
          ],
        ),
      );
}
