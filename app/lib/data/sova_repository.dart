import 'models.dart';

/// Everything the app needs from the backend. The demo implementation runs
/// in memory; the API implementation will talk to Sova's server, which talks
/// to Neon. Screens only ever see this interface.
abstract interface class SovaRepository {
  /// Sends a one-time code to [phone] (E.164, e.g. +2348031234567).
  Future<void> requestOtp(String phone);

  /// Exchanges the code for a session. Throws [SovaException] if wrong.
  Future<Session> verifyOtp(String phone, String code);

  Future<Session> saveProfile({required String fullName, required String pin});

  /// Checks the PIN before money-related actions. Five wrong tries locks it.
  Future<void> verifyPin(String pin);

  Future<List<Circle>> myCircles();

  Future<Circle> circle(String id);

  /// The signed-in member says they've paid this round's collector.
  Future<Contribution> confirmMyPayment({
    required String circleId,
    required String roundId,
    String? bankReference,
    bool hasProof = false,
  });

  /// The collector confirms they received a member's payment.
  Future<Contribution> confirmReceived({required String circleId, required String contributionId});

  Future<void> acceptRules(String circleId);

  /// Starts a circle with the signed-in member as admin. The admin accepts
  /// the rules by creating it.
  Future<Circle> createCircle(NewCircle draft);

  /// Looks up a circle by its 6-character invite code, before joining.
  Future<Circle> findByInviteCode(String code);

  /// Joins with an invite code. [voucherId] is the member who invited you and
  /// vouches for you; joining also accepts the group's rules.
  Future<Circle> joinCircle({required String code, required String voucherId});
}

class SovaException implements Exception {
  const SovaException(this.message);
  final String message;

  @override
  String toString() => message;
}
