import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/api_repository.dart';
import 'api/session_store.dart';
import 'demo_repository.dart';
import 'models.dart';
import 'sova_repository.dart';

/// The API address, set at build time:
///   flutter run --dart-define=SOVA_API_URL=https://sova-api.rumptycloud.app
/// Without it the app runs on the in-memory demo backend.
const apiUrl = String.fromEnvironment('SOVA_API_URL');

/// The public website, home of the "Verify this circle" page.
const siteUrl = String.fromEnvironment('SOVA_SITE_URL', defaultValue: 'https://sova.rumptycloud.app');

final repositoryProvider = Provider<SovaRepository>(
  (ref) => apiUrl.isEmpty ? DemoRepository() : ApiRepository(ApiClient(baseUrl: apiUrl, store: createSessionStore())),
);

class AuthState {
  const AuthState({this.restoring = true, this.onboarded = false, this.pendingPhone, this.session});

  /// Checking for a saved session at start-up.
  final bool restoring;
  final bool onboarded;

  /// Phone number a code was sent to, while waiting for the OTP.
  final String? pendingPhone;
  final Session? session;

  bool get signedIn => session != null;
  bool get ready => session?.profileComplete ?? false;

  AuthState copyWith({
    bool? restoring,
    bool? onboarded,
    String? pendingPhone,
    Session? session,
    bool clearSession = false,
    bool clearPendingPhone = false,
  }) =>
      AuthState(
        restoring: restoring ?? this.restoring,
        onboarded: onboarded ?? this.onboarded,
        pendingPhone: clearPendingPhone ? null : (pendingPhone ?? this.pendingPhone),
        session: clearSession ? null : (session ?? this.session),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState();
  }

  SovaRepository get _repo => ref.read(repositoryProvider);

  /// Picks up the session saved on this device (or in this browser tab).
  Future<void> _restore() async {
    Session? session;
    try {
      session = await _repo.restoreSession();
    } on SovaException {
      session = null; // Offline or server down: start signed out rather than stuck.
    }
    state = state.copyWith(restoring: false, session: session, onboarded: session != null ? true : null);
  }

  void finishOnboarding() => state = state.copyWith(onboarded: true);

  Future<void> requestOtp(String phone) async {
    await _repo.requestOtp(phone);
    state = state.copyWith(pendingPhone: phone);
  }

  /// Back to the phone screen to fix a mistyped number.
  void changeNumber() => state = state.copyWith(clearPendingPhone: true);

  Future<void> verifyOtp(String code) async {
    final session = await _repo.verifyOtp(state.pendingPhone!, code);
    state = state.copyWith(session: session);
  }

  /// "Try the demo": straight into the shared demo account.
  Future<void> startDemo() async {
    final session = await _repo.startDemo();
    state = state.copyWith(onboarded: true, session: session, clearPendingPhone: true);
  }

  Future<void> saveProfile({required String fullName, required String pin}) async {
    final session = await _repo.saveProfile(fullName: fullName, pin: pin);
    state = state.copyWith(session: session);
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = AuthState(restoring: false, onboarded: state.onboarded);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// The signed-in member's user id ('' while signed out).
final meProvider = Provider<String>((ref) => ref.watch(authProvider.select((s) => s.session?.userId ?? '')));

final circlesProvider = FutureProvider<List<Circle>>((ref) {
  ref.watch(meProvider);
  return ref.watch(repositoryProvider).myCircles();
});

final circleProvider = FutureProvider.family<Circle, String>((ref, id) {
  return ref.watch(repositoryProvider).circle(id);
});

/// Refresh every view of a circle after something changes.
void refreshCircle(WidgetRef ref, String id) {
  ref.invalidate(circleProvider(id));
  ref.invalidate(circlesProvider);
}
