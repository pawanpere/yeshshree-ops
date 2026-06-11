/// Session state: tokens, role/station, language. Persisted in shared_preferences
/// (tokens are short-lived + the refresh token is opaque & rotated server-side; move
/// to flutter_secure_storage when platform setup lands — noted in packet record).
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'strings.dart';

class Session {
  const Session({this.accessToken, this.refreshToken, this.role, this.station,
      this.fullName, this.username, this.language = 'en', this.deviceKey});
  final String? accessToken;
  final String? refreshToken;
  final String? role;
  final String? station;
  final String? fullName;
  final String? username;
  final String language;
  final String? deviceKey; // set when this install is a registered station device

  bool get loggedIn => accessToken != null;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken, 'refreshToken': refreshToken, 'role': role,
        'station': station, 'fullName': fullName, 'username': username,
        'language': language, 'deviceKey': deviceKey,
      };

  static Session fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        role: j['role'] as String?,
        station: j['station'] as String?,
        fullName: j['fullName'] as String?,
        username: j['username'] as String?,
        language: (j['language'] as String?) ?? 'en',
        deviceKey: j['deviceKey'] as String?,
      );
}

class AuthNotifier extends Notifier<Session> {
  static const _key = 'session_v1';

  @override
  Session build() {
    Api.wire();
    Api.readToken = () => state.accessToken;
    Api.tryRefresh = _refresh;
    Api.forceLogout = logout;
    _restore();
    return const Session();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      state = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      S.lang.value = state.language;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }

  void _applyTokens(Map<String, dynamic> body, {String? username}) {
    state = Session(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      role: body['role'] as String?,
      station: body['station'] as String?,
      fullName: body['full_name'] as String?,
      username: username ?? state.username,
      language: (body['language'] as String?) ?? 'en',
      deviceKey: state.deviceKey,
    );
    S.lang.value = state.language;
    _persist();
  }

  Future<void> login(String username, String password) async {
    final r = await Api.dio.post('/auth/login', data: {
      'username': username, 'password': password, 'device_key': state.deviceKey,
    });
    _applyTokens(r.data as Map<String, dynamic>, username: username);
  }

  Future<void> pinSwitch(String username, String pin) async {
    final r = await Api.dio.post('/auth/pin-switch', data: {
      'device_key': state.deviceKey, 'username': username, 'pin': pin,
    });
    _applyTokens(r.data as Map<String, dynamic>, username: username);
  }

  Future<String?> requestOtp(String phone) async {
    final r = await Api.dio.post('/auth/vendor-otp/request', data: {'phone': phone});
    return (r.data as Map<String, dynamic>)['dev_code'] as String?; // mock OTP
  }

  Future<void> verifyOtp(String phone, String code) async {
    final r = await Api.dio
        .post('/auth/vendor-otp/verify', data: {'phone': phone, 'code': code});
    _applyTokens(r.data as Map<String, dynamic>, username: phone);
  }

  Future<bool> _refresh() async {
    final rt = state.refreshToken;
    if (rt == null) return false;
    try {
      final r = await Api.dio.post('/auth/refresh', data: {'refresh_token': rt});
      _applyTokens(r.data as Map<String, dynamic>);
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> setDeviceKey(String? key) async {
    state = Session.fromJson({...state.toJson(), 'deviceKey': key});
    await _persist();
  }

  Future<void> logout() async {
    final rt = state.refreshToken;
    final dk = state.deviceKey;
    try {
      if (rt != null) await Api.dio.post('/auth/logout', data: {'refresh_token': rt});
    } catch (_) {}
    state = Session(deviceKey: dk); // device registration survives user logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }
}

final authProvider = NotifierProvider<AuthNotifier, Session>(AuthNotifier.new);
