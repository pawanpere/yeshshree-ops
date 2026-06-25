/// Data layer for the standalone OCR demo service (`yeshshree-ops/demo/api.py`).
///
/// Kept SEPARATE from [Api] (core/api_client.dart): that client targets the
/// ops-2 backend at `/api/v1` and auto-injects a bearer token. The OCR service is
/// a tokenless demo helper on its own port (default :8900) that wraps the Google
/// Vision OCR + dummy-PO match + GRN-Excel pipeline. Override the host with
/// `--dart-define=OCR_URL=http://<host>:<port>`.
///
/// Every call swallows transport errors and returns null / empty, so the scan
/// screen can show a clean "OCR service offline" state instead of throwing.
import 'package:dio/dio.dart';

typedef Json = Map<String, dynamic>;

/// The decoded-scan poll envelope from `GET /ocr/latest`.
class OcrPoll {
  const OcrPoll({required this.latestId, this.entry});

  /// Highest scan id the service has (0 if none yet).
  final int latestId;

  /// The newest decoded scan (id > the `after` we asked with), or null if there
  /// is nothing newer to show.
  final Json? entry;
}

class Ocr {
  Ocr._();

  static const base =
      String.fromEnvironment('OCR_URL', defaultValue: 'http://localhost:8900');

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 4),
    // Vision OCR on a scanned page can take a few seconds — be generous.
    receiveTimeout: const Duration(seconds: 90),
    sendTimeout: const Duration(seconds: 30),
  ));

  /// Service health: `{ok, has_key, pos}`. null when the service is unreachable —
  /// the scan screen uses this to tell the operator to start the OCR service and
  /// whether a Google Vision key is wired in.
  static Future<Json?> health() async {
    try {
      final r = await _dio.get('/ocr/health');
      return (r.data is Map) ? Json.from(r.data as Map) : null;
    } on DioException {
      return null;
    }
  }

  /// The dummy open-PO list (the manual-pick fallback when OCR finds no match).
  static Future<List<Json>> pos() async {
    try {
      final r = await _dio.get('/ocr/pos');
      return (r.data is List)
          ? [for (final e in (r.data as List)) Json.from(e as Map)]
          : const <Json>[];
    } on DioException {
      return const <Json>[];
    }
  }

  /// Poll for the newest decoded scan beyond [after] (the ScanJet folder-watch
  /// path). null when the service is unreachable.
  static Future<OcrPoll?> latest({int after = 0}) async {
    try {
      final r = await _dio.get('/ocr/latest', queryParameters: {'after': after});
      final m = Json.from(r.data as Map);
      final e = m['entry'];
      return OcrPoll(
        latestId: (m['latest_id'] as num?)?.toInt() ?? 0,
        entry: e == null ? null : Json.from(e as Map),
      );
    } on DioException {
      return null;
    }
  }

  /// OCR one of the bundled dummy invoices (named by PO) — the no-scanner demo
  /// path. Returns the decoded entry, or null on transport failure.
  static Future<Json?> ingestSample(String poNo) async {
    try {
      final r = await _dio.post('/ocr/ingest-sample', data: {'po_no': poNo});
      final m = Json.from(r.data as Map);
      final e = m['entry'];
      return e == null ? null : Json.from(e as Map);
    } on DioException {
      return null;
    }
  }

  /// Generate the SAP-ready GRN Excel for a matched PO; returns the GRN number
  /// (e.g. `GR-2026-0001`) or null on failure.
  static Future<String?> generateGrn(Json body) async {
    try {
      final r = await _dio.post('/ocr/grn', data: body);
      return (r.data is Map) ? (Json.from(r.data as Map)['grn_no'] as String?) : null;
    } on DioException {
      return null;
    }
  }

  /// Absolute URL to download a generated GRN sheet (handed to the browser).
  static String grnDownloadUrl(String grnNo) => '$base/ocr/grn/$grnNo.xlsx';
}
