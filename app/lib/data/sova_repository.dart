import 'dart:typed_data';

import 'models.dart';

/// Everything the app needs from the backend. [ApiRepository] talks to the
/// Sova API; [DemoRepository] runs in memory for tests and offline demos.
/// Screens only ever see this interface.
///
/// Money actions take the member's PIN: the server checks it as part of the
/// action, so a stolen session alone can't record or confirm payments.
abstract interface class SovaRepository {
  /// A hint shown on the code screen (the demo code), or null in production.
  String? get otpHint;

  /// The session saved on this device, or null. Called once at start-up.
  Future<Session?> restoreSession();

  /// Sends a one-time code to [phone] (E.164, e.g. +2348031234567).
  Future<void> requestOtp(String phone);

  /// Exchanges the code for a session. Throws [SovaException] if wrong.
  Future<Session> verifyOtp(String phone, String code);

  /// Signs in to the shared demo account ("Try the demo").
  Future<Session> startDemo();

  Future<void> signOut();

  Future<Session> saveProfile({required String fullName, required String pin});

  /// Checks the PIN. Five wrong tries locks it for 15 minutes.
  Future<void> verifyPin(String pin);

  Future<List<Circle>> myCircles();

  Future<Circle> circle(String id);

  /// Starts a circle with the signed-in member as admin and first member.
  Future<Circle> createCircle(NewCircle draft, {required String pin});

  /// Looks up a circle by its 6-character invite code, before joining.
  Future<Circle> findByInviteCode(String code);

  /// Joins with an invite code, accepting rules [rulesVersion]. [voucherId] is
  /// the member who vouches for the newcomer. The last member to join starts
  /// the circle: turns are drawn and turn 1 opens.
  Future<Circle> joinCircle({
    required String code,
    String? voucherId,
    required int rulesVersion,
    required String pin,
  });

  Future<Circle> acceptRules(String circleId, int version);

  /// Uploads a photo of the payment receipt for this turn and returns its
  /// key, to pass to [confirmMyPayment]. The server keeps it in private
  /// storage; only members of the circle can view it.
  Future<String> uploadProof({
    required String circleId,
    required int roundNumber,
    required Uint8List bytes,
    required String contentType,
  });

  /// A short-lived link to view a payment's receipt photo.
  Future<String> proofUrl(String contributionId);

  /// The signed-in member says they've paid this turn's collector.
  Future<Circle> confirmMyPayment({
    required String circleId,
    required int roundNumber,
    String? bankReference,
    String? proofKey,
    required String pin,
  });

  /// The collector confirms a member's payment arrived.
  Future<Circle> confirmReceived({required String circleId, required String contributionId, required String pin});

  /// The collector confirms what reached them and closes the turn. A short
  /// payout opens a dispute; the circle moves on either way.
  Future<PayoutResult> confirmPayout({
    required String circleId,
    required int roundNumber,
    required int amount,
    required String pin,
  });

  /// The circle's disputes, open ones first. Timelines are left out.
  Future<List<Dispute>> disputes(String circleId);

  /// One dispute with its votes and timeline.
  Future<Dispute> dispute(String id);

  /// The collector says a payment marked as sent hasn't arrived, or the payer
  /// says it isn't being confirmed. The payment is frozen while the circle decides.
  Future<Dispute> raiseDispute({required String contributionId, required String reason, required String pin});

  /// Members other than the payer and collector vote on whether the money
  /// arrived; more than half of them decides. A vote can change while open.
  Future<Dispute> voteDispute({required String disputeId, required DisputeSide side, required String pin});

  /// A party closes the dispute by agreeing with the other side.
  Future<Dispute> settleDispute({required String disputeId, required String pin});

  Future<Dispute> commentOnDispute({required String disputeId, required String message});

  /// The signed-in member's Sova Score, worked out live from their record.
  Future<SovaScore> myScore();

  /// Publishes a snapshot of the score behind a new private link, replacing
  /// any live one. Refused until there is enough history.
  Future<SovaScore> shareScore({required String pin});

  /// Stops sharing: the link stops working straight away.
  Future<SovaScore> stopSharingScore();
}

class SovaException implements Exception {
  const SovaException(this.message, {this.code});
  final String message;

  /// Machine-readable reason from the server, e.g. 'wrong_pin'.
  final String? code;

  @override
  String toString() => message;
}
