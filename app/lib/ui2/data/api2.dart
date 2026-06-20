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

  // ---------------------------------------------------------------- reads ---

  static Future<Loaded<List<Json>>> _list(
    String path, {
    Map<String, dynamic>? query,
    required List<Json> demo,
    bool demoIfEmpty = false,
  }) async {
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

  static Future<Loaded<List<Json>>> dispatches() =>
      _list('/dispatches', query: {'status': 'open'},
          demo: demoDispatches, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> notifications() =>
      _list('/notifications', demo: demoNotifications, demoIfEmpty: true);

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
    try {
      final r = await Api.dio.post(path, data: body);
      return WriteResult(WriteStatus.ok,
          data: r.data is Map ? Json.from(r.data as Map) : null);
    } on DioException catch (e) {
      return WriteResult(WriteStatus.error, error: ApiException.from(e));
    }
  }

  static String newRef() => _uuid.v4();

  // ----------------------------------------------------------- demo data ---
  // Mirrors the values the prototype screens display, used as fallback so the
  // app is fully functional offline / against an empty DB. Marked DEMO in UI.

  static const demoMaterials = <Json>[
    {'sap_code': 'CR-25', 'description': 'CR coil 2.5mm', 'uom': 'KG', 'price': '52.74'},
    {'sap_code': 'CR-30', 'description': 'CR coil 3.0mm', 'uom': 'KG', 'price': '54.10'},
    {'sap_code': 'FAST-M8', 'description': 'Fasteners M8', 'uom': 'BOX', 'price': '180.00'},
  ];
  static const demoLines = <Json>[
    {'id': 1, 'name': 'Line A', 'plant': '1117'},
    {'id': 2, 'name': 'Line B', 'plant': '1117'},
  ];
  static const demoReasons = <Json>[
    {'code': 'MISCOUNT', 'label_en': 'Miscount at handover', 'label_mr': 'हस्तांतरणात चुकीची मोजणी'},
    {'code': 'REWORK', 'label_en': 'Sent for rework', 'label_mr': 'पुनःकामासाठी पाठवले'},
    {'code': 'TOOL', 'label_en': 'Tool / die issue', 'label_mr': 'टूल / डाय समस्या'},
    {'code': 'MATERIAL', 'label_en': 'Material defect', 'label_mr': 'मटेरियल दोष'},
  ];
  static const demoCustomers = <Json>[
    {'sap_code': 'C-100', 'name': 'Sunrise Metals', 'gstin': '27ABCDE1234F1Z5'},
    {'sap_code': 'C-101', 'name': 'Deccan Recyclers', 'gstin': '27ZYXWV9876K1A2'},
  ];
  static const demoPurchaseOrders = <Json>[
    {'sap_po_no': '77-2291', 'vendor': 'Sandhar Steel', 'material': 'CR coil 2.5mm', 'open_qty': '4000', 'rate': '52.74'},
  ];
  static const demoVendors = <Json>[
    {'sap_code': 'V-1', 'name': 'Sandhar Steel'},
    {'sap_code': 'V-2', 'name': 'Bharat Forge'},
  ];
  static const demoGateArrivals = <Json>[
    {'vehicle': 'MH12 AB 4421', 'supplier': 'Sandhar Steel', 'eta': '11:00', 'status': 'new'},
    {'vehicle': 'MH14 CD 9032', 'supplier': 'Bharat Forge', 'eta': '11:30', 'status': 'new'},
    {'vehicle': 'MH09 KL 2210', 'supplier': '—', 'eta': '—', 'status': 'unmatched'},
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
  // Matched gate entries awaiting inward QC (the quality worklist cards). One raw
  // material (weighed) + one component (counted) so the QC branch is demonstrable.
  static const demoQualityWorklist = <Json>[
    {'id': 11, 'vehicle': 'MH12 AB 4421', 'supplier': 'Sandhar Steel',
     'invoice': 'INV-3131079408', 'material': 'CR coil 2.5mm', 'category': 'rm',
     'qty_expected': '4000'},
    {'id': 12, 'vehicle': 'MH14 CD 9032', 'supplier': 'Bharat Forge',
     'invoice': 'INV-7740221', 'material': 'Fasteners M8', 'category': 'component',
     'qty_expected': '2400'},
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
