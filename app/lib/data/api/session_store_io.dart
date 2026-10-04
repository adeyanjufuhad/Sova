import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_store.dart';

const _key = 'sova.refresh_token';

SessionStore createSessionStore() => _SecureSessionStore();

class _SecureSessionStore implements SessionStore {
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? refreshToken) =>
      refreshToken == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: refreshToken);
}
