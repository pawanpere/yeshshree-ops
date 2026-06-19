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

  static Future<Loaded<Json>> _one(
    String path, {
    required Json demo,
  }) async {
    try {
      final r = await Api.dio.get(path);
      final raw = r.data;
      if (raw is Map) return Loaded(Json.from(raw));
      return Loaded(demo, demo: true);
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

  // Transactional reads — tables are empty in dev.db, so these mostly DEMO.
  static Future<Loaded<List<Json>>> gateArrivals() => _list(
      '/gate-entries', query: {'status': 'pending'},
      demo: demoGateArrivals, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> confirmationsHistory() => _list(
      '/confirmations', query: {'today': true},
      demo: demoConfirmations, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> dispatches() =>
      _list('/dispatches', query: {'status': 'open'},
          demo: demoDispatches, demoIfEmpty: true);

  static Future<Loaded<List<Json>>> notifications() =>
      _list('/notifications', demo: demoNotifications, demoIfEmpty: true);

  static Future<Loaded<Json>> cockpit() =>
      _one('/dashboards/line-cockpit', demo: demoCockpit);

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
  static const demoConfirmations = <Json>[
    {'part': 'Front fork 4521', 'qty': '60', 'time': '15:10', 'doc': 'PC-2261', 'reject': '2'},
    {'part': 'Front fork 4521', 'qty': '48', 'time': '14:05', 'doc': 'PC-2258', 'reject': '0'},
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
  static const demoCockpit = <String, dynamic>{
    'plan': 200, 'done': 132, 'pct': 66, 'yield': 96, 'downtime': 22,
    'projected': 198, 'status': 'running',
  };
}
