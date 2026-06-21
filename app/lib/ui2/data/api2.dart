/// Data layer for the ui2 phone app.
///
/// Reads go through [Api.dio] (the existing hand-written Dio core — the bearer
/// token is auto-injected by its interceptor once a session exists). Writes go
/// through [retryQueueProvider] with a `client_ref` UUID, exactly as the
/// existing `features/` screens do (ARCHITECTURE.md rules 2–4).
///
/// Every read falls back to clearly-marked DEMO data when the backend is
/// unreachable OR when a transactional table is still empty — so the app is
/// fully functional whether or not the API is up. Screens show a "DEMO DATA"
/// marker when [Loaded.demo] is true.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/retry_queue.dart';

/// A read result tagged with whether it came from the live API or DEMO fallback.
class Loaded<T> {
  const Loaded(this.data, {this.demo = false});
  final T data;
  final bool demo;
}

/// Outcome of a transactional write.
enum WriteStatus { ok, queued, error }

class WriteResult {
  const WriteResult(this.status, {this.data, this.error});
  final WriteStatus status;
  final Map<String, dynamic>? data;
  final ApiException? error;

  bool get ok => status == WriteStatus.ok;
  bool get queued => status == WriteStatus.queued;
  bool get failed => status == WriteStatus.error;
}

typedef Json = Map<String, dynamic>;

class Data {
  Data._();
  static const _uuid = Uuid();

  /// Offline preview mode (the `?role=` dev deep-link). When on, every read returns
  /// DEMO data and every write is simulated as OK — NO network at all. This keeps
  /// the preview self-contained and immune to the live backend (whose 401 on the
  /// fake demo token would otherwise force-logout and bounce back to the picker).
  static bool demoMode = false;

  // ---------------------------------------------------------------- reads ---

  static Future<Loaded<List<Json>>> _list(
    String path, {
    Map<String, dynamic>? query,
    required List<Json> demo,
    bool demoIfEmpty = false,
  }) async {
    if (demoMode) return Loaded(demo, demo: true);
    try {
      final r = await Api.dio.get(path, queryParameters: query);
      final raw = r.data;
      final rows = (raw is List)
          ? raw.map((e) => Json.from(e as Map)).toList()
          : <Json>[];
      if (rows.isEmpty && demoIfEmpty) return Loaded(demo, demo: true);
      return Loaded(rows);
    } on DioException {
      return Loaded(demo, demo: true);
    }
  }

  /// Single-object read (e.g. a dashboard summary), with a DEMO fallback.
  static Future<Loaded<Json>> _one(String path, {required Json demo}) async {
    if (demoMode) return Loaded(demo, demo: true);
    try {
      final r = await Api.dio.get(path);
      return (r.data is Map) ? Loaded(Json.from(r.data as Map)) : Loaded(demo, demo: true);
    } on DioException {
      return Loaded(demo, demo: true);
    }
  }

  // Master data — real rows exist in dev.db.
  static Future<Loaded<List<Json>>> materials({String? q}) =>
      _list('/master/materials',
          query: {'limit': 50, if (q != null && q.isNotEmpty) 'q': q},
          demo: demoMaterials);

  static Future<Loaded<List<Json>>> lines() =>
      _list('/master/lines', demo: demoLines);

  static Future<Loaded<List<Json>>> reasonCodes({String kind = 'reject'}) =>
      _list('/config/reason-codes',
          query: {'kind': kind}, demo: demoReasons, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> customers() =>
      _list('/master/customers', demo: demoCustomers, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> purchaseOrders({int? vendorId}) =>
      _list('/master/purchase-orders',
          query: {if (vendorId != null) 'vendor_id': vendorId},
          demo: demoPurchaseOrders);

  static Future<Loaded<List<Json>>> vendors() =>
      _list('/master/vendors', demo: demoVendors);

  /// Local (plant-local) calendar date as `YYYY-MM-DD` — the value backend date
  /// filters expect. The device runs in the plant's timezone, so `DateTime.now()`
  /// is already local; we only need the date part.
  static String todayIso() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // Transactional reads — tables are empty in dev.db, so these mostly DEMO.

  /// Gate inbox: OPEN entries (status=open; 'pending' is not a valid status).
  /// Live `GateEntryRead` rows are normalised to the stable display shape the
  /// arrivals screen reads ({vehicle, supplier, eta, status}).
  static Future<Loaded<List<Json>>> gateArrivals() async {
    final res = await _list('/gate-entries', query: {'status': 'open'},
        demo: demoGateArrivals, demoIfEmpty: true);
    if (res.demo) return res;
    return Loaded([for (final e in res.data) _gateArrivalRow(e)]);
  }

  static Json _gateArrivalRow(Json e) {
    final matched = '${e['match_status'] ?? ''}'.toLowerCase() == 'matched';
    final st = '${e['status'] ?? ''}'.toLowerCase();
    return {
      'vehicle': e['vehicle_no'],
      'supplier': e['vendor_name_text'] ?? '—',
      'eta': '—',
      'status': st == 'gr_done' ? 'done' : (matched ? 'new' : 'unmatched'),
    };
  }

  /// Today's confirmations for the line (date=today, not the old `today=true`).
  /// Live `ConfirmationRead` rows are enriched with the material description so the
  /// history screen can show a name instead of a bare material_id.
  static Future<Loaded<List<Json>>> confirmationsHistory({int? lineId}) async {
    final res = await _list('/confirmations',
        query: {'date': todayIso(), if (lineId != null) 'line_id': lineId},
        demo: demoConfirmations, demoIfEmpty: true);
    if (res.demo) return res;
    final mats = await materials();
    final byId = {for (final m in mats.data) m['id']: m['description']};
    return Loaded([
      for (final c in res.data)
        {
          ...c,
          'material_name': byId[c['material_id']] ?? 'Material #${c['material_id']}',
          // Unify the sync pill key across live (sap_sync_status) and demo.
          'sync_status': c['sap_sync_status'] ?? c['status'] ?? 'posted',
        },
    ]);
  }

  /// Supervisor plan view for a line + today (the production cockpit's source).
  static Future<Loaded<List<Json>>> supervisorView({required int lineId}) =>
      _list('/plans/supervisor-view',
          query: {'line_id': lineId, 'date': todayIso()},
          demo: demoSupervisorRows, demoIfEmpty: true);

  /// Production routings — the ordered operations a part runs through (press →
  /// weld → assembly …) with the qty completed at each. Source of truth is SAP
  /// routing; here it falls back to demo data shaped like the SAP feed so the
  /// WIP board works without a backend. `done` per op derives WIP between stations.
  static Future<Loaded<List<Json>>> productionRoutings({int? lineId}) =>
      _list('/production/routings',
          query: {if (lineId != null) 'line_id': lineId},
          demo: demoRoutings, demoIfEmpty: true);

  /// Record completion AFTER a single operation (mid-operation confirmation) so
  /// WIP advances one station. Posts to WIP-at-operation on the backend; a normal
  /// transactional write (client_ref + retry queue).
  static Future<WriteResult> submitOperationConfirmation(
          WidgetRef ref, Map<String, dynamic> body) =>
      submit(ref, '/operation-confirmations', body,
          label: 'Operation ${body['operation_name'] ?? ''}');

  /// Open approvals the signed-in user can act on (drives the approval card).
  static Future<Loaded<List<Json>>> approvalsInbox() =>
      _list('/approvals/inbox', demo: demoApprovals, demoIfEmpty: true);

  /// Quality worklist: gate entries that passed the gate and are MATCHED to a PO,
  /// waiting for inward QC (status=open & match_status=matched). Live rows are
  /// normalised + enriched with the material description for the worklist cards.
  static Future<Loaded<List<Json>>> qualityWorklist() async {
    final res = await _list('/gate-entries',
        query: {'status': 'open', 'match_status': 'matched'},
        demo: demoQualityWorklist, demoIfEmpty: true);
    if (res.demo) return res;
    final mats = await materials();
    final byId = {for (final m in mats.data) m['id']: m};
    return Loaded([
      for (final e in res.data)
        {
          'id': e['id'],
          'vehicle': e['vehicle_no'],
          'supplier': e['vendor_name_text'] ?? '—',
          'invoice': e['invoice_no'] ?? e['doc_no'],
          'material': byId[e['material_id']]?['description'] ??
              (e['material_id'] != null ? 'Material #${e['material_id']}' : '—'),
          // Plant stock category drives the QC branch (component = counted pieces,
          // rm = weighed on the weighbridge).
          'category': byId[e['material_id']]?['category'] ?? 'rm',
          'qty_expected': e['qty_expected'],
        },
    ]);
  }

  // Admin: users + station devices (admin-only endpoints).
  static Future<Loaded<List<Json>>> users({bool activeOnly = true}) =>
      _list('/master/users', query: {'active_only': activeOnly},
          demo: demoUsers, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> stationDevices({bool activeOnly = true}) =>
      _list('/master/station-devices', query: {'active_only': activeOnly},
          demo: demoStationDevices, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> dispatches() =>
      _list('/dispatches', query: {'status': 'open'},
          demo: demoDispatches, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> notifications() =>
      _list('/notifications', demo: demoNotifications, demoIfEmpty: true);

  // ---- Phase 6: office / store / vendor reads ----

  /// Management one-screen KPI summary.
  static Future<Loaded<Json>> overview() =>
      _one('/dashboards/overview', demo: demoOverview);

  /// Anomaly register (open by default).
  static Future<Loaded<List<Json>>> anomalies({String status = 'open'}) =>
      _list('/anomalies', query: {'status': status},
          demo: demoAnomalies, demoIfEmpty: true);

  /// Today's line plans (all lines) — planning + dashboards.
  static Future<Loaded<List<Json>>> linePlans({String? date}) =>
      _list('/plans/line-plans', query: {'date': date ?? todayIso()},
          demo: demoLinePlans, demoIfEmpty: true);

  /// Open production holds (waiting for a SAP order) — planning + production.
  static Future<Loaded<List<Json>>> holds({String status = 'open'}) =>
      _list('/confirmations/holds', query: {'status': status},
          demo: demoHolds, demoIfEmpty: true);

  /// Current stock balances per material/location (store stock browse). The live
  /// BalanceRead carries only {material_id, location, vendor_id, qty}, so enrich
  /// each row with the material description + uom (same pattern as the other reads).
  static Future<Loaded<List<Json>>> stockBalances({String? location}) async {
    final res = await _list('/stock/balances',
        query: {if (location != null) 'location': location},
        demo: demoStockBalances, demoIfEmpty: true);
    if (res.demo) return res;
    final mats = await materials();
    final byId = {for (final m in mats.data) m['id']: m};
    return Loaded([
      for (final b in res.data)
        {
          ...b,
          'material': byId[b['material_id']]?['description'] ??
              (b['material_id'] != null ? 'Material #${b['material_id']}' : '—'),
          'uom': byId[b['material_id']]?['uom'] ?? '',
        },
    ]);
  }

  /// System settings (ops_mode + thresholds) — admin settings.
  static Future<Loaded<List<Json>>> settings() =>
      _list('/config/settings', demo: demoSettings, demoIfEmpty: true);

  /// Resolve a held confirmation by giving PPC's SAP order number.
  static Future<WriteResult> resolveHold(int holdId, String sapOrderNo) =>
      mutate('/confirmations/holds/$holdId/resolve', {'sap_order_no': sapOrderNo});

  /// Mark an anomaly reviewed/resolved.
  static Future<WriteResult> resolveAnomaly(int anomalyId, String note) =>
      mutate('/anomalies/$anomalyId/resolve', {'note': note});

  // ---- vendor portal (scoped to the signed-in vendor on the server) ----
  static Future<Loaded<List<Json>>> vendorOrders() =>
      _list('/vendor/purchase-orders', demo: demoVendorOrders, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> vendorCalloffs() =>
      _list('/vendor/calloffs', demo: demoVendorCalloffs, demoIfEmpty: true);

  static Future<Loaded<Json>> vendorExposure() =>
      _one('/vendor/exposure', demo: demoVendorExposure);

  static Future<Loaded<List<Json>>> vendorDebitNotes() =>
      _list('/vendor/debit-notes', demo: demoVendorDebitNotes, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> vendorStock() =>
      _list('/vendor/stock', demo: demoVendorStock, demoIfEmpty: true);

  // --------------------------------------------------------------- writes ---

  /// Transactional POST through the retry queue. A fresh `client_ref` is added
  /// if absent (idempotency key). Returns [WriteResult]: ok / queued-offline /
  /// error (a real 4xx envelope).
  static Future<WriteResult> submit(
    WidgetRef ref,
    String path,
    Map<String, dynamic> body, {
    required String label,
  }) async {
    body.putIfAbsent('client_ref', () => _uuid.v4());
    if (demoMode) return WriteResult(WriteStatus.ok, data: _demoWrite(body));
    try {
      final res =
          await ref.read(retryQueueProvider.notifier).post(path, body, label: label);
      return res == null
          ? const WriteResult(WriteStatus.queued)
          : WriteResult(WriteStatus.ok, data: res);
    } on ApiException catch (e) {
      return WriteResult(WriteStatus.error, error: e);
    }
  }

  /// Non-transactional mutation (approve/decline, mark-read). Direct POST.
  static Future<WriteResult> mutate(
      String path, Map<String, dynamic> body) async {
    if (demoMode) return WriteResult(WriteStatus.ok, data: _demoWrite(body));
    try {
      final r = await Api.dio.post(path, data: body);
      return WriteResult(WriteStatus.ok,
          data: r.data is Map ? Json.from(r.data as Map) : null);
    } on DioException catch (e) {
      return WriteResult(WriteStatus.error, error: ApiException.from(e));
    }
  }

  /// PATCH update (admin master/user/device edits). Direct, non-transactional.
  static Future<WriteResult> patch(
      String path, Map<String, dynamic> body) async {
    if (demoMode) return WriteResult(WriteStatus.ok, data: _demoWrite(body));
    try {
      final r = await Api.dio.patch(path, data: body);
      return WriteResult(WriteStatus.ok,
          data: r.data is Map ? Json.from(r.data as Map) : null);
    } on DioException catch (e) {
      return WriteResult(WriteStatus.error, error: ApiException.from(e));
    }
  }

  /// A plausible success payload for a simulated write in demo mode (echoes the
  /// body + a fake id/doc_no so result screens have something to show).
  static Json _demoWrite(Map<String, dynamic> body) =>
      {...body, 'id': 1, 'doc_no': 'DEMO-0001'};

  static String newRef() => _uuid.v4();

  // ----------------------------------------------------------- demo data ---
  // Mirrors the values the prototype screens display, used as fallback so the
  // app is fully functional offline / against an empty DB. Marked DEMO in UI.

  // Materials need a stable `id`: the issue/production material pickers key the
  // selection by it, and the issue form gates on a real material_id — a null id
  // left the Issue button permanently disabled.
  static const demoMaterials = <Json>[
    {'id': 1, 'sap_code': 'CR-25', 'description': 'CR coil 2.5mm', 'uom': 'KG', 'price': '52.74'},
    {'id': 2, 'sap_code': 'CR-30', 'description': 'CR coil 3.0mm', 'uom': 'KG', 'price': '54.10'},
    {'id': 3, 'sap_code': 'FAST-M8', 'description': 'Fasteners M8', 'uom': 'BOX', 'price': '180.00'},
  ];
  static const demoLines = <Json>[
    {'id': 1, 'name': 'Line A', 'plant': '1117'},
    {'id': 2, 'name': 'Line B', 'plant': '1117'},
  ];
  // Each reason needs a stable `id`: the reject/override pickers key options by it
  // (a null id makes every option indistinguishable AND leaves reject_reason_id
  // null, so "Pick a reject reason" never clears).
  static const demoReasons = <Json>[
    {'id': 1, 'code': 'MISCOUNT', 'label_en': 'Miscount at handover', 'label_mr': 'हस्तांतरणात चुकीची मोजणी'},
    {'id': 2, 'code': 'REWORK', 'label_en': 'Sent for rework', 'label_mr': 'पुनःकामासाठी पाठवले'},
    {'id': 3, 'code': 'TOOL', 'label_en': 'Tool / die issue', 'label_mr': 'टूल / डाय समस्या'},
    {'id': 4, 'code': 'MATERIAL', 'label_en': 'Material defect', 'label_mr': 'मटेरियल दोष'},
  ];
  // Master rows carry a stable `id` (pickers key the selection by it; a null id
  // leaves an id-gated CTA permanently disabled).
  static const demoCustomers = <Json>[
    {'id': 1, 'sap_code': 'C-100', 'name': 'Sunrise Metals', 'gstin': '27ABCDE1234F1Z5'},
    {'id': 2, 'sap_code': 'C-101', 'name': 'Deccan Recyclers', 'gstin': '27ZYXWV9876K1A2'},
  ];
  static const demoPurchaseOrders = <Json>[
    {'sap_po_no': '77-2291', 'vendor': 'Sandhar Steel', 'material': 'CR coil 2.5mm', 'open_qty': '4000', 'rate': '52.74'},
  ];
  static const demoVendors = <Json>[
    {'id': 1, 'sap_code': 'V-1', 'name': 'Sandhar Steel'},
    {'id': 2, 'sap_code': 'V-2', 'name': 'Bharat Forge'},
  ];
  // Gate inbox. A deliberate mix so tapping different rows shows real variety:
  // raw-material coil deliveries (weighed in kg) AND purchased components (counted
  // in pcs), from distinct vendors, plus one unknown/no-pre-advice walk-in. Each
  // row carries its own material/category/PO/ordered/challan so the match + QC
  // steps reflect *that* entry instead of a single hard-coded order. `ordered`
  // and `challan` are bare numbers; the unit is derived from `category`
  // (rm → kg, component → pcs). One RM row is short vs its PO to exercise the
  // tolerance chip.
  // Each OPEN row carries `arrived_hours_ago` so the screen derives a live GRN
  // deadline (arrival + 3 days; P-T) — a spread that exercises ok / due-soon /
  // overdue states. Items carry `on_hand`/`stock_max`/`stock_min` so the receive
  // screen can enforce the max stock limit (P-L): CR coil + Fasteners are near
  // their max, so their full challan can't be accepted.
  static const demoGateArrivals = <Json>[
    // Multi-item invoices (P-G): one challan carrying several materials, whose
    // lines sit against DIFFERENT POs. Tapping one opens the Receive Invoice
    // screen where every line is entered together.
    {'vehicle': 'MH40 PQ 8833', 'supplier': 'Sandhar Steel', 'eta': '11:30',
     'status': 'new', 'invoice': 'INV-9931002', 'arrived_hours_ago': 6, 'items': [
       {'material': 'CR coil 2.5mm', 'category': 'rm', 'po': '77-2291', 'ordered': '4000', 'challan': '4000', 'on_hand': '2800', 'stock_max': '3000', 'stock_min': '500'},
       {'material': 'HR coil 3.0mm', 'category': 'rm', 'po': '77-2304', 'ordered': '6000', 'challan': '5860', 'on_hand': '1000', 'stock_max': '12000', 'stock_min': '800'},
       {'material': 'Mounting bracket 7782', 'category': 'component', 'po': '88-4419', 'ordered': '1500', 'challan': '1500', 'on_hand': '200', 'stock_max': '5000', 'stock_min': '300'},
       {'material': 'Fasteners M8 hex', 'category': 'component', 'po': '88-4631', 'ordered': '8000', 'challan': '8000', 'on_hand': '7950', 'stock_max': '8000', 'stock_min': '1000'},
     ]},
    {'vehicle': 'MH43 RS 2207', 'supplier': 'Precision Fasteners', 'eta': '12:30',
     'status': 'new', 'invoice': 'INV-7740999', 'arrived_hours_ago': 65, 'items': [
       {'material': 'Spacer clip 12mm', 'category': 'component', 'po': '88-4631', 'ordered': '20000', 'challan': '20000', 'on_hand': '9600', 'stock_max': '40000', 'stock_min': '5000'},
       {'material': 'Forged lever arm 5519', 'category': 'component', 'po': '88-5001', 'ordered': '1200', 'challan': '1180', 'on_hand': '300', 'stock_max': '4000', 'stock_min': '400'},
     ]},
    {'vehicle': 'MH12 AB 4421', 'supplier': 'Tata Steel BSL', 'eta': '11:00',
     'status': 'new', 'category': 'rm', 'material': 'CR coil 2.5mm',
     'po': '77-2291', 'ordered': '4000', 'challan': '4000', 'arrived_hours_ago': 30,
     'on_hand': '2800', 'stock_max': '3000', 'stock_min': '500',
     'invoice': 'INV-3131079408'},
    {'vehicle': 'MH14 CD 9032', 'supplier': 'Mahalaxmi Components', 'eta': '11:20',
     'status': 'new', 'category': 'component', 'material': 'Mounting bracket 7782',
     'po': '88-4419', 'ordered': '1500', 'challan': '1500', 'arrived_hours_ago': 50,
     'on_hand': '200', 'stock_max': '5000', 'stock_min': '300',
     'invoice': 'INV-7740221'},
    {'vehicle': 'MH09 KL 2210', 'supplier': '—', 'eta': '—', 'status': 'unmatched'},
    {'vehicle': 'MH04 GT 7788', 'supplier': 'Sandhar Steel', 'eta': '11:45',
     'status': 'new', 'category': 'rm', 'material': 'HR coil 3.0mm',
     'po': '77-2304', 'ordered': '6000', 'challan': '5860', 'arrived_hours_ago': 70,
     'on_hand': '1000', 'stock_max': '12000', 'stock_min': '800',
     'invoice': 'INV-5521003'},
    {'vehicle': 'MH12 ZX 1190', 'supplier': 'Precision Fasteners', 'eta': '12:10',
     'status': 'new', 'category': 'component', 'material': 'Fasteners M8 hex',
     'po': '88-4631', 'ordered': '8000', 'challan': '8000', 'arrived_hours_ago': 74,
     'on_hand': '7950', 'stock_max': '8000', 'stock_min': '1000',
     'invoice': 'INV-7740555'},
    {'vehicle': 'MH02 BR 5521', 'supplier': 'Bharat Forge', 'eta': '—',
     'status': 'done', 'category': 'component', 'material': 'Forged lever arm 5519',
     'po': '88-5001', 'ordered': '1200', 'challan': '1200',
     'invoice': 'INV-6610897'},
  ];
  // Shape mirrors enriched ConfirmationRead (+ material_name) so the live and demo
  // code paths in the history screen are identical. posted_at is ISO; the screen
  // shows HH:mm. sync_status: synced | queued | posted.
  static const demoConfirmations = <Json>[
    {'id': 3, 'material_name': 'Front fork 4521', 'good_qty': '60', 'rejected_qty': '2',
     'status': 'posted', 'posted_at': '2026-06-20T15:10:00', 'sync_status': 'synced'},
    {'id': 2, 'material_name': 'Front fork 4521', 'good_qty': '48', 'rejected_qty': '0',
     'status': 'posted', 'posted_at': '2026-06-20T14:02:00', 'sync_status': 'queued'},
    {'id': 1, 'material_name': 'Front fork 4521', 'good_qty': '52', 'rejected_qty': '0',
     'status': 'posted', 'posted_at': '2026-06-20T12:40:00', 'sync_status': 'posted'},
  ];
  // Mirrors SupervisorRow (one row per planned material on the line). Aggregates to
  // 200 planned · 132 good · 6 reject → 95.6% yield, 68 remaining.
  static const demoSupervisorRows = <Json>[
    {'plan_id': 1, 'line_id': 1, 'line_name': 'Line A', 'material_id': 10,
     'sap_code': '1402010035', 'description': 'Front fork 4521', 'revision': 1,
     'planned_qty': '200', 'confirmed_good': '132', 'confirmed_reject': '6',
     'remaining': '68', 'sap_order_no': '100482'},
  ];
  // Production routings (P-W) — each part's ordered operations with the qty that
  // has CLEARED each one. WIP between two stations = done[i] − done[i+1]; the last
  // op's output is finished goods. Mirrors the SAP routing feed shape.
  static const demoRoutings = <Json>[
    {'material_id': 10, 'material': 'Front fork 4521', 'line': 'Line A', 'plan': '200',
     'operations': [
       {'seq': 10, 'name': 'Blanking', 'wc': 'Press 250T', 'done': '200'},
       {'seq': 20, 'name': 'Forming', 'wc': 'Press 160T', 'done': '170'},
       {'seq': 30, 'name': 'Welding', 'wc': 'Weld cell 2', 'done': '150'},
       {'seq': 40, 'name': 'Assembly', 'wc': 'Assy line 1', 'done': '132'},
     ]},
    {'material_id': 11, 'material': 'Mounting bracket 7782', 'line': 'Line B', 'plan': '300',
     'operations': [
       {'seq': 10, 'name': 'Blanking', 'wc': 'Press 200T', 'done': '300'},
       {'seq': 20, 'name': 'Piercing', 'wc': 'Press 120T', 'done': '286'},
       {'seq': 30, 'name': 'Bending', 'wc': 'Press brake 1', 'done': '270'},
       {'seq': 40, 'name': 'Welding', 'wc': 'Weld cell 1', 'done': '252'},
     ]},
  ];
  // ---- Phase 6 demos ----
  // 7-day achievement % trend (for the management dashboard sparkline/chart).
  static const demoMgmtTrend = <double>[58, 63, 61, 67, 71, 64, 66];
  // Management KPI summary (mirror OverviewOut).
  static const demoOverview = <String, dynamic>{
    'date': '2026-06-20', 'achievement_pct': '66', 'billed_today_value': '1840000',
    'yield_pct': '96', 'open_anomalies': {'total': 3, 'hard': 1},
    'approvals_pending': 2, 'open_override_reviews': 0,
    'unmatched_gate_entries': 2, 'outbox_backlog': {'pending': 4, 'failed': 0},
    'holds_open': 1,
  };
  // Anomaly register (mirror AnomalyRead).
  static const demoAnomalies = <Json>[
    {'id': 1, 'rule_code': 'SHORTAGE_5X', 'severity': 'hard', 'ref_type': 'goods_receipt',
     'ref_id': 88, 'message_en': 'Receipt 4.2% short of PO — debit raised',
     'message_mr': 'पावती PO पेक्षा 4.2% कमी — डेबिट केले', 'status': 'open'},
    {'id': 2, 'rule_code': 'REJECT_SPIKE', 'severity': 'soft', 'ref_type': 'confirmation',
     'ref_id': 261, 'message_en': 'Reject rate 2× the line average',
     'message_mr': 'नापास दर लाईन सरासरीच्या 2×', 'status': 'open'},
    {'id': 3, 'rule_code': 'PLAN_EXCEED', 'severity': 'soft', 'ref_type': 'confirmation',
     'ref_id': 262, 'message_en': 'Confirmed 24% over plan',
     'message_mr': 'नियोजनापेक्षा 24% जास्त पुष्टी', 'status': 'open'},
  ];
  // Today's line plans (mirror PlanRow).
  static const demoLinePlans = <Json>[
    {'plan_id': 1, 'line_id': 1, 'line_name': 'Line A', 'material_id': 10,
     'sap_code': '1402010035', 'description': 'Front fork 4521', 'revision': 1,
     'planned_qty': '200', 'confirmed_good': '132', 'confirmed_reject': '6', 'remaining': '68'},
    {'plan_id': 2, 'line_id': 2, 'line_name': 'Line B', 'material_id': 11,
     'sap_code': '1402010044', 'description': 'Bracket 7782', 'revision': 1,
     'planned_qty': '300', 'confirmed_good': '252', 'confirmed_reject': '3', 'remaining': '48'},
  ];
  // Open production holds (mirror HoldRead; payload carries the confirmation body).
  static const demoHolds = <Json>[
    {'id': 1, 'line_id': 1, 'material_id': 10, 'status': 'open',
     'payload': {'line_id': 1, 'shift': 'B', 'material_id': 10, 'good_qty': '48',
                 'rejected_qty': '0', 'material': 'Front fork 4521'}},
  ];
  // Stock balances (mirror BalanceRead).
  static const demoStockBalances = <Json>[
    {'material_id': 1, 'material': 'CR coil 2.5mm', 'location': 'RM', 'vendor_id': null, 'qty': '28090', 'uom': 'KG'},
    {'material_id': 2, 'material': 'CR coil 3.0mm', 'location': 'RM', 'vendor_id': null, 'qty': '12400', 'uom': 'KG'},
    {'material_id': 3, 'material': 'Fasteners M8', 'location': 'COMP', 'vendor_id': null, 'qty': '8600', 'uom': 'EA'},
    {'material_id': 1, 'material': 'CR coil 2.5mm', 'location': 'AT_VENDOR', 'vendor_id': 1, 'qty': '5000', 'uom': 'KG'},
    {'material_id': 10, 'material': 'Front fork 4521', 'location': 'FG', 'vendor_id': null, 'qty': '320', 'uom': 'EA'},
  ];
  // System settings (mirror SettingRead {key,value}).
  static const demoSettings = <Json>[
    {'key': 'ops_mode', 'value': {'mode': 'parallel_run'}},
    {'key': 'anomaly_thresholds', 'value': {'hard_qty_multiple': 5, 'soft_deviation_pct': 20,
        'rejection_spike_factor': 2.0, 'plan_exceed_pct': 20}},
    {'key': 'debit_note', 'value': {'multiplier': 5}},
  ];
  // Vendor portal demos — a COMPONENT supplier (fasteners/brackets), not RM steel.
  static const demoVendorOrders = <Json>[
    {'id': 1, 'sap_po_no': '520000845', 'item_no': 1, 'material_id': 30,
     'material': 'Fasteners M8 hex', 'ordered_qty': '50000', 'open_qty': '24000',
     'rate': '12', 'uom': 'EA', 'due_date': '2026-06-25', 'status': 'open'},
    {'id': 2, 'sap_po_no': '520000846', 'item_no': 1, 'material_id': 31,
     'material': 'Mounting bracket 7782', 'ordered_qty': '8000', 'open_qty': '0',
     'rate': '46', 'uom': 'EA', 'due_date': '2026-06-18', 'status': 'open'},
    {'id': 3, 'sap_po_no': '520000851', 'item_no': 1, 'material_id': 32,
     'material': 'Spacer clip 12mm', 'ordered_qty': '20000', 'open_qty': '15400',
     'rate': '4', 'uom': 'EA', 'due_date': '2026-07-02', 'status': 'open'},
  ];
  static const demoVendorCalloffs = <Json>[
    {'id': 1, 'material_id': 30, 'material': 'Fasteners M8 hex', 'calloff_date': '2026-06-22',
     'qty': '6000', 'status': 'open'},
    {'id': 2, 'material_id': 32, 'material': 'Spacer clip 12mm', 'calloff_date': '2026-06-29',
     'qty': '5000', 'status': 'planned'},
  ];
  static const demoVendorExposure = <String, dynamic>{
    'vendor_id': 1, 'credit_exposure': '1450000', 'qty_mt': '34',
    'credit_limit': '2500000', 'qty_limit_mt': '60',
  };
  static const demoVendorDebitNotes = <Json>[
    {'id': 1, 'doc_no': 'DN-2261', 'kind': 'shortage_5x', 'base_amount': '8400',
     'amount': '42000', 'status': 'draft'},
  ];
  static const demoVendorStock = <Json>[
    {'material_id': 30, 'material': 'Fasteners M8 hex', 'qty': '24000', 'uom': 'EA'},
    {'material_id': 32, 'material': 'Spacer clip 12mm', 'qty': '9600', 'uom': 'EA'},
  ];
  // Admin: demo users + station devices (mirror UserRead / StationDeviceRead).
  static const demoUsers = <Json>[
    {'id': 1, 'username': 'admin', 'full_name': 'Kartik (Admin)', 'role': 'admin',
     'station': null, 'phone': null, 'language': 'en', 'is_active': true, 'has_pin': false},
    {'id': 2, 'username': 'sunita', 'full_name': 'Sunita P.', 'role': 'supervisor',
     'station': null, 'phone': '+91 98xxxxxx01', 'language': 'mr', 'is_active': true, 'has_pin': true},
    {'id': 3, 'username': 'gate1', 'full_name': 'Ravi (Gate)', 'role': 'plant_ops',
     'station': 'gate', 'phone': null, 'language': 'mr', 'is_active': true, 'has_pin': true},
    {'id': 4, 'username': 'anil', 'full_name': 'Anil (PPC)', 'role': 'planning',
     'station': null, 'phone': null, 'language': 'en', 'is_active': true, 'has_pin': false},
  ];
  static const demoStationDevices = <Json>[
    {'id': 1, 'device_key': 'gate-kiosk-1', 'station': 'gate', 'label': 'Gate scanner kiosk',
     'registered_by': 1, 'last_seen_at': '2026-06-20T13:40:00', 'is_active': true},
    {'id': 2, 'device_key': 'qc-tablet-2', 'station': 'qc', 'label': 'QC tablet',
     'registered_by': 1, 'last_seen_at': '2026-06-20T12:05:00', 'is_active': true},
    {'id': 3, 'device_key': 'store-tablet-1', 'station': 'store', 'label': 'Store tablet',
     'registered_by': 1, 'last_seen_at': null, 'is_active': true},
  ];
  // Matched gate entries awaiting inward QC (the quality worklist cards). One raw
  // material (weighed) + one component (counted) so the QC branch is demonstrable.
  static const demoQualityWorklist = <Json>[
    {'id': 11, 'vehicle': 'MH12 AB 4421', 'supplier': 'Tata Steel BSL',
     'invoice': 'INV-3131079408', 'material': 'CR coil 2.5mm', 'category': 'rm',
     'qty_expected': '4000'},
    {'id': 12, 'vehicle': 'MH14 CD 9032', 'supplier': 'Mahalaxmi Components',
     'invoice': 'INV-7740221', 'material': 'Fasteners M8 hex', 'category': 'component',
     'qty_expected': '6000'},
    {'id': 13, 'vehicle': 'MH04 GT 7788', 'supplier': 'Sandhar Steel',
     'invoice': 'INV-5521003', 'material': 'CR coil 3.0mm', 'category': 'rm',
     'qty_expected': '2800'},
    {'id': 14, 'vehicle': 'MH12 ZX 1190', 'supplier': 'Precision Fasteners',
     'invoice': 'INV-9982271', 'material': 'Mounting bracket 7782',
     'category': 'component', 'qty_expected': '1500'},
    {'id': 15, 'vehicle': 'MH02 BR 5521', 'supplier': 'Mahalaxmi Components',
     'invoice': 'INV-7740555', 'material': 'Spacer clip 12mm', 'category': 'component',
     'qty_expected': '8000'},
  ];
  // Mirrors ApprovalRead; payload carries a bilingual summary for the card.
  static const demoApprovals = <Json>[
    {'id': 1, 'approval_type': 'credit_waiver', 'ref_type': 'issues', 'ref_id': 1,
     'status': 'open', 'required_roles': ['management'],
     'payload': {'who': 'Sunita',
                 'summary_en': "+250 kg CR coil over today's limit",
                 'summary_mr': 'आजच्या मर्यादेपेक्षा +250 kg CR coil'}},
  ];
  static const demoDispatches = <Json>[
    {'do': 'DO-3391', 'customer': 'Bajaj Auto', 'detail': '320 pc front fork', 'status': 'ready'},
    {'do': 'DO-3390', 'customer': 'Bajaj Auto', 'detail': '200 pc bracket', 'status': 'open'},
    {'do': 'DO-3388', 'customer': 'Mahindra', 'detail': '150 pc lever', 'status': 'open'},
  ];
  static const demoNotifications = <Json>[
    {'kind': 'approval', 'title': 'Permission needed — extra issue', 'body': 'Sunita asks for +250 kg CR coil over the daily limit', 'unread': true},
    {'kind': 'warn', 'title': 'Line B behind plan', 'body': '84% at 2 pm', 'unread': true},
    {'kind': 'info', 'title': 'Schedule wk-25 released', 'body': '1:10 pm', 'unread': false},
  ];
}
