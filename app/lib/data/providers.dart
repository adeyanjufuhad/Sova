import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo_repository.dart';
import 'models.dart';
import 'sova_repository.dart';

/// Swap DemoRepository for the API-backed repository once the server is live.
final repositoryProvider = Provider<SovaRepository>((ref) => DemoRepository());

class AuthState {
  const AuthState({this.onboarded = false, this.pendingPhone, this.session});

  final bool onboarded;

  /// Phone number a code was sent to, while waiting for the OTP.
  final String? pendingPhone;
  final Session? session;

  bool get signedIn => session != null;
  bool get ready => session?.profileComplete ?? false;

  AuthState copyWith({
    bool? onboarded,
    String? pendingPhone,
    Session? session,
    bool clearSession = false,
    bool clearPendingPhone = false,
  }) =>
      AuthState(
        onboarded: onboarded ?? this.onboarded,
        pendingPhone: clearPendingPhone ? null : (pendingPhone ?? this.pendingPhone),
        session: clearSession ? null : (session ?? this.session),
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  SovaRepository get _repo => ref.read(repositoryProvider);

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

  Future<void> saveProfile({required String fullName, required String pin}) async {
    final session = await _repo.saveProfile(fullName: fullName, pin: pin);
    state = state.copyWith(session: session);
  }

  void signOut() => state = AuthState(onboarded: state.onboarded);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final circlesProvider = FutureProvider<List<Circle>>((ref) {
  ref.watch(authProvider.select((s) => s.session?.userId));
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
