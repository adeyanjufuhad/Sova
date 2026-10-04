import 'package:web/web.dart' as web;

import 'session_store.dart';

const _key = 'sova.refresh_token';

SessionStore createSessionStore() => _TabSessionStore();

/// sessionStorage: scoped to this tab, cleared when it closes.
class _TabSessionStore implements SessionStore {
  @override
  Future<String?> read() async => web.window.sessionStorage.getItem(_key);

  @override
  Future<void> write(String? refreshToken) async {
    if (refreshToken == null) {
      web.window.sessionStorage.removeItem(_key);
    } else {
      web.window.sessionStorage.setItem(_key, refreshToken);
    }
  }
}
