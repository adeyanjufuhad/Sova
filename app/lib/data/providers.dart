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
  const AuthState({
    this.restoring = true,
    this.onboarded = false,
    this.pendingPhone,
    this.pendingEmail,
    this.suggestedName,
    this.session,
  });

  /// Checking for a saved session at start-up.
  final bool restoring;
  final bool onboarded;

  /// Phone number a code was sent to, while waiting for the OTP.
  final String? pendingPhone;

  /// Email address a code was sent to, while waiting for it.
  final String? pendingEmail;

  /// The name on a Google account, to prefill a new profile.
  final String? suggestedName;
  final Session? session;

  bool get signedIn => session != null;

  /// A code was sent (by SMS or email) and the code screen is showing.
  bool get awaitingCode => pendingPhone != null || pendingEmail != null;
  bool get ready => session?.profileComplete ?? false;

  AuthState copyWith({
    bool? restoring,
    bool? onboarded,
    String? pendingPhone,
    String? pendingEmail,
    String? suggestedName,
    Session? session,
    bool clearSession = false,
    bool clearPendingPhone = false,
  }) =>
      AuthState(
        restoring: restoring ?? this.restoring,
        onboarded: onboarded ?? this.onboarded,
        pendingPhone: clearPendingPhone ? null : (pendingPhone ?? this.pendingPhone),
        pendingEmail: clearPendingPhone ? null : (pendingEmail ?? this.pendingEmail),
        suggestedName: suggestedName ?? this.suggestedName,
        session: clearSession ? null : (session ?? this.session),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    // The server ended the session: back to sign-in rather than an error on every screen.
    final expired = _repo.sessionExpired.listen((_) {
      if (state.signedIn) state = AuthState(restoring: false, onboarded: state.onboarded);
    });
    ref.onDispose(expired.cancel);
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

  Future<void> requestEmailCode(String email) async {
    await _repo.requestEmailCode(email);
    state = state.copyWith(pendingEmail: email);
  }

  /// Back to the sign-in screen to fix a mistyped number or email.
  void changeNumber() => state = state.copyWith(clearPendingPhone: true);

  /// Checks the code sent to the pending phone or email.
  Future<void> verifyOtp(String code) async {
    final email = state.pendingEmail;
    final session = email != null ? await _repo.verifyEmailCode(email, code) : await _repo.verifyOtp(state.pendingPhone!, code);
    state = state.copyWith(session: session);
  }

  /// "Continue with Google", once Google has handed over an ID token.
  Future<void> signInWithGoogle(String idToken) async {
    final (session, name) = await _repo.signInWithGoogle(idToken);
    state = state.copyWith(onboarded: true, session: session, suggestedName: name, clearPendingPhone: true);
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

  Future<void> updateName(String fullName) async {
    final session = await _repo.updateName(fullName);
    state = state.copyWith(session: session);
  }

  Future<void> saveBank(BankDetails bank, {required String pin}) async {
    final session = await _repo.saveBank(bank: bank, pin: pin);
    state = state.copyWith(session: session);
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = AuthState(restoring: false, onboarded: state.onboarded);
  }

  /// A guided tour was finished or skipped: it isn't offered again. If the
  /// server can't be told, it is simply offered again next time.
  Future<void> finishTour(Tour tour) async {
    final s = state.session;
    if (s == null || !s.pendingTours.contains(tour)) return;
    state = state.copyWith(session: s.copyWith(pendingTours: {...s.pendingTours}..remove(tour)));
    try {
      await _repo.markTourDone(tour);
    } on SovaException {
      // Offered again on the next sign-in.
    }
  }

  /// After the account was deleted (the repository already ended the session).
  void accountDeleted() => state = AuthState(restoring: false, onboarded: state.onboarded);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Which ways to sign in the backend offers (email codes, Google).
final signInMethodsProvider = FutureProvider<SignInMethods>((ref) => ref.read(repositoryProvider).signInMethods());

/// The signed-in member's user id ('' while signed out).
final meProvider = Provider<String>((ref) => ref.watch(authProvider.select((s) => s.session?.userId ?? '')));

final circlesProvider = FutureProvider<List<Circle>>((ref) {
  ref.watch(meProvider);
  return ref.watch(repositoryProvider).myCircles();
});

final circleProvider = FutureProvider.family<Circle, String>((ref, id) {
  return ref.watch(repositoryProvider).circle(id);
});

final scoreProvider = FutureProvider<SovaScore>((ref) {
  ref.watch(meProvider);
  return ref.watch(repositoryProvider).myScore();
});

final inboxProvider = FutureProvider<Inbox>((ref) {
  ref.watch(meProvider);
  return ref.watch(repositoryProvider).notifications();
});

final turnChangesProvider = FutureProvider.family<TurnChanges, String>((ref, circleId) {
  return ref.watch(repositoryProvider).turnChanges(circleId);
});

final handoverOffersProvider = FutureProvider<List<HandoverOffer>>((ref) {
  ref.watch(meProvider);
  return ref.watch(repositoryProvider).handoverOffers();
});

final disputesProvider = FutureProvider.family<List<Dispute>, String>((ref, circleId) {
  return ref.watch(repositoryProvider).disputes(circleId);
});

final disputeProvider = FutureProvider.family<Dispute, String>((ref, id) {
  return ref.watch(repositoryProvider).dispute(id);
});

/// Refresh every view of a circle after something changes.
void refreshCircle(WidgetRef ref, String id) {
  ref.invalidate(circleProvider(id));
  ref.invalidate(circlesProvider);
  ref.invalidate(scoreProvider);
  ref.invalidate(disputesProvider(id));
  ref.invalidate(turnChangesProvider(id));
  ref.invalidate(inboxProvider);
}
