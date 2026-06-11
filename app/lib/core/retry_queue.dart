/// Client retry queue (plan decision 5: online-only + retry). Failed POSTs whose
/// bodies carry a client_ref are queued locally and drained when connectivity returns —
/// the backend's idempotency (invariant 4) makes blind re-fire safe: a duplicate
/// returns the ORIGINAL result, never a second document.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class QueuedPost {
  QueuedPost({required this.path, required this.body, required this.queuedAt,
      required this.label});
  final String path;
  final Map<String, dynamic> body; // must contain client_ref
  final DateTime queuedAt;
  final String label; // user-facing, e.g. 'Confirmation 40 pcs Front Body'

  Map<String, dynamic> toJson() => {'path': path, 'body': body,
      'queuedAt': queuedAt.toIso8601String(), 'label': label};

  static QueuedPost fromJson(Map<String, dynamic> j) => QueuedPost(
      path: j['path'] as String,
      body: Map<String, dynamic>.from(j['body'] as Map),
      queuedAt: DateTime.parse(j['queuedAt'] as String),
      label: j['label'] as String);
}

class RetryQueue extends Notifier<List<QueuedPost>> {
  static const _key = 'retry_queue_v1';
  Timer? _timer;

  @override
  List<QueuedPost> build() {
    _restore();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => drain());
    ref.onDispose(() => _timer?.cancel());
    return const [];
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    state = raw
        .map((s) => QueuedPost.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, state.map((q) => jsonEncode(q.toJson())).toList());
  }

  /// POST with offline-queueing. Returns the response data, or null if queued.
  Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body,
      {required String label}) async {
    assert(body.containsKey('client_ref'), 'queueable posts need a client_ref');
    try {
      final r = await Api.dio.post(path, data: body);
      return r.data as Map<String, dynamic>?;
    } on DioException catch (e) {
      final ex = ApiException.from(e);
      if (ex.code == 'OFFLINE') {
        state = [...state, QueuedPost(path: path, body: body,
            queuedAt: DateTime.now(), label: label)];
        await _persist();
        return null; // caller shows "queued — will sync"
      }
      throw ex; // real (4xx) errors surface immediately
    }
  }

  Future<void> drain() async {
    if (state.isEmpty) return;
    final remaining = <QueuedPost>[];
    for (final q in state) {
      try {
        await Api.dio.post(q.path, data: q.body);
      } on DioException catch (e) {
        final ex = ApiException.from(e);
        if (ex.code == 'OFFLINE') {
          remaining.add(q); // still offline — keep, preserve order
          remaining.addAll(state.sublist(state.indexOf(q) + 1));
          break;
        }
        // 4xx after the fact (e.g. validation): drop from queue — the record is
        // visible in history/anomalies server-side; never retry a rejected doc.
      }
    }
    state = remaining;
    await _persist();
  }
}

final retryQueueProvider =
    NotifierProvider<RetryQueue, List<QueuedPost>>(RetryQueue.new);
