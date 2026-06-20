/// Dio HTTP core: bearer injection, one-shot refresh on 401, error-envelope parsing,
/// clock-skew detection (§11.15). Domain clients in lib/api/ build on `Api.dio`.
///
/// NOTE (packet record): clients are HAND-WRITTEN 1:1 against backend/docs/openapi.json
/// for now — the generated-client step (CLAUDE.md convention) activates on the dev
/// machine where openapi-generator can run; the swap is mechanical because every
/// endpoint/model here mirrors the spec exactly.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'strings.dart';

class ApiException implements Exception {
  ApiException({required this.code, required this.messageEn, required this.messageMr,
      this.details = const {}, this.status});
  final String code;
  final String messageEn;
  final String messageMr;
  final Map<String, dynamic> details;
  final int? status;

  String get message => S.lang.value == 'mr' ? messageMr : messageEn;

  @override
  String toString() => message; // AsyncBody renders snap.error.toString()

  static ApiException from(DioException e) {
    final data = e.response?.data;
    final detail = (data is Map && data['detail'] is Map) ? data['detail'] as Map : null;
    if (detail != null && detail['code'] != null) {
      return ApiException(
        code: detail['code'] as String,
        messageEn: (detail['message_en'] ?? detail['code']) as String,
        messageMr: (detail['message_mr'] ?? detail['message_en'] ?? '') as String,
        details: Map<String, dynamic>.from(detail['details'] as Map? ?? {}),
        status: e.response?.statusCode,
      );
    }
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    return ApiException(
      code: offline ? 'OFFLINE' : 'UNKNOWN',
      messageEn: offline ? 'No connection — will retry' : 'Something went wrong',
      messageMr: offline ? 'कनेक्शन नाही — पुन्हा प्रयत्न होईल' : 'काहीतरी चूक झाली',
      status: e.response?.statusCode,
    );
  }

  /// §11.15: 401 envelopes carry details.server_time — a big skew means the device
  /// clock is wrong, which reads as "login failed" without this hint.
  bool get isClockSkew {
    final st = details['server_time'];
    if (st is! String) return false;
    final server = DateTime.tryParse(st);
    if (server == null) return false;
    return DateTime.now().toUtc().difference(server.toUtc()).abs() >
        const Duration(minutes: 2);
  }
}

typedef TokenReader = String? Function();
typedef RefreshFn = Future<bool> Function();
typedef LogoutFn = Future<void> Function();

class Api {
  static const baseUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

  static final dio = Dio(BaseOptions(
    baseUrl: '$baseUrl/api/v1',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// The local fake access token used by the offline `?role=` demo preview. The
  /// live backend 401s it; we must NOT treat that as a real session expiry.
  static const demoToken = 'demo';

  /// Wired once by auth_state at startup (avoids a circular import).
  static TokenReader readToken = () => null;
  static RefreshFn tryRefresh = () async => false;
  static LogoutFn forceLogout = () async {};

  static bool _wired = false;

  static void wire() {
    if (_wired) return;
    _wired = true;
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = readToken();
        if (t != null && !options.path.startsWith('/auth/')) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401 &&
            e.requestOptions.extra['retried'] != true &&
            // The demo preview's fake token always 401s — never refresh/force-logout
            // it, or the offline ?role= preview would log itself out on every read.
            readToken() != demoToken &&
            !e.requestOptions.path.startsWith('/auth/')) {
          if (await tryRefresh()) {
            final opts = e.requestOptions..extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${readToken()}';
            try {
              final res = await dio.fetch(opts);
              return handler.resolve(res);
            } on DioException catch (e2) {
              return handler.next(e2);
            }
          }
          await forceLogout();
        }
        handler.next(e);
      },
    ));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
    }
  }
}
