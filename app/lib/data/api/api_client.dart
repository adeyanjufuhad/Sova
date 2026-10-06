import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../sova_repository.dart';
import 'session_store.dart';

/// JSON over HTTPS to the Sova API.
///
/// * Keeps the access token in memory and the refresh token in [SessionStore].
/// * On a 401 it refreshes once (shared by concurrent requests) and retries.
/// * The host may be asleep (free deployments sleep when idle) and answer with
///   a "waking" page for a few seconds; requests wait and retry meanwhile.
/// * Errors become [SovaException] with the server's message and code.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.store,
    http.Client? client,
    this.wakeRetryDelay = const Duration(seconds: 2),
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl),
        _http = client ?? http.Client();

  final Uri _base;
  final http.Client _http;
  final SessionStore store;
  final Duration wakeRetryDelay;

  static const _maxWakeRetries = 20;

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshing;

  bool get hasSession => _refreshToken != null;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  /// Sends a file (e.g. a receipt photo) as the raw request body.
  Future<dynamic> postBytes(String path, Uint8List bytes, String contentType) =>
      _send('POST', path, bytes: bytes, contentType: contentType);

  /// Stores the pair returned by sign-in endpoints and returns the user JSON.
  Future<Map<String, dynamic>> startSession(Map<String, dynamic> response) async {
    _accessToken = response['accessToken'] as String;
    _refreshToken = response['refreshToken'] as String;
    await store.write(_refreshToken);
    return response['user'] as Map<String, dynamic>;
  }

  /// Uses the saved refresh token, if any. Returns the user JSON or null.
  Future<Map<String, dynamic>?> resume() async {
    _refreshToken = await store.read();
    if (_refreshToken == null) return null;
    try {
      final res = await _send('POST', '/auth/refresh', body: {'refreshToken': _refreshToken}, auth: false);
      return startSession(res as Map<String, dynamic>);
    } on SovaException catch (e) {
      // An expired or revoked session just means signing in again.
      if (e.code == 'unauthorized' || e.code == 'invalid_request') {
        await endSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> endSession({bool tellServer = false}) async {
    final token = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    await store.write(null);
    if (tellServer && token != null) {
      try {
        await _send('POST', '/auth/logout', body: {'refreshToken': token}, auth: false);
      } on SovaException {
        // Signing out locally is what matters.
      }
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Uint8List? bytes,
    String? contentType,
    bool auth = true,
    bool retried = false,
  }) async {
    final res = await _withWake(() {
      final req = http.Request(method, _base.resolve(path));
      req.headers['Accept'] = 'application/json';
      if (bytes != null) {
        req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
        req.bodyBytes = bytes;
      } else if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      if (auth && _accessToken != null) req.headers['Authorization'] = 'Bearer $_accessToken';
      return _http.send(req).then(http.Response.fromStream);
    });

    if (res.statusCode == 401 && auth && !retried && _refreshToken != null && await _refresh()) {
      return _send(method, path, body: body, bytes: bytes, contentType: contentType, auth: auth, retried: true);
    }
    if (res.statusCode == 204 || res.body.isEmpty) return null;

    final dynamic json;
    try {
      json = jsonDecode(res.body);
    } on FormatException {
      throw const SovaException('Sova is having trouble right now. Please try again in a moment.');
    }
    if (res.statusCode >= 400) {
      final error = (json is Map ? json['error'] : null) as Map<String, dynamic>?;
      throw SovaException(
        (error?['message'] as String?) ?? 'Something went wrong. Please try again.',
        code: error?['code'] as String?,
      );
    }
    return json;
  }

  /// One refresh at a time; concurrent 401s wait for the same attempt.
  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final res = await _send('POST', '/auth/refresh', body: {'refreshToken': _refreshToken}, auth: false);
        await startSession(res as Map<String, dynamic>);
        return true;
      } on SovaException {
        await endSession();
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// Retries while the host serves its "waking up" page or can't be reached.
  Future<http.Response> _withWake(Future<http.Response> Function() send) async {
    for (var attempt = 0;; attempt++) {
      http.Response res;
      try {
        res = await send();
      } on http.ClientException {
        if (attempt >= 2) throw const SovaException('No connection. Check your internet and try again.', code: 'offline');
        await Future<void>.delayed(wakeRetryDelay);
        continue;
      }
      final waking = res.body.contains('data-rumpty-wake') ||
          ((res.statusCode == 502 || res.statusCode == 503) && !(res.headers['content-type'] ?? '').contains('json'));
      if (!waking) return res;
      if (attempt >= _maxWakeRetries) {
        throw const SovaException('Sova is starting up. Please try again in a minute.', code: 'waking');
      }
      await Future<void>.delayed(wakeRetryDelay);
    }
  }
}
