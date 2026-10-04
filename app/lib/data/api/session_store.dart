import 'session_store_io.dart' if (dart.library.js_interop) 'session_store_web.dart' as platform;

/// Where the refresh token lives between app launches.
///
/// Android: the Keystore-backed secure storage. Web: the tab's sessionStorage,
/// so the session survives a reload but ends when the tab closes, and never
/// sits in long-lived browser storage. Only the refresh token is stored; the
/// short-lived access token stays in memory.
abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String? refreshToken);
}

SessionStore createSessionStore() => platform.createSessionStore();

/// For tests and anything that must not touch the device.
class MemorySessionStore implements SessionStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String? refreshToken) async => _value = refreshToken;
}
