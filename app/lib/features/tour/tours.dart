import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/sova_router.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/tour.dart';

/// The main tour: home, then each tab. Offered once after sign-in (a new
/// account, or every private demo) and replayable from the Record tab.
void startHomeTour(BuildContext context, WidgetRef ref) {
  final session = ref.read(authProvider).session;
  final demo = session?.isDemo ?? false;
  final router = GoRouter.of(context);

  showTour(context, [
    TourStep(
      title: 'Welcome to Sova',
      body: demo
          ? 'This is your own private demo with pretend people and money, so tap anything. '
                'Your demo PIN is $demoAccountPin. Here\'s a quick look around.'
          : 'Sova keeps the record for your ajo, esusu or adashe. Members pay each other directly; '
                'Sova never holds the money. Here\'s a quick look around.',
      before: () => router.go(SovaRoutes.home),
    ),
    const TourStep(
      target: 'home.payout',
      title: 'Your next payout',
      body:
          'When your turn comes, every other member pays you once. This shows how much and when. '
          'Tap the eye to hide amounts.',
    ),
    const TourStep(
      target: 'home.actions',
      title: 'Pay, start or join',
      body:
          'Record a payment you\'ve sent, start a circle of your own, or join one with the 6-letter code a friend shares.',
    ),
    const TourStep(
      target: 'home.bell',
      title: 'Reminders',
      body: 'What\'s due soon, what\'s late, and payments waiting for you to confirm.',
    ),
    if (session?.assistant ?? false)
      const TourStep(
        target: 'home.ask',
        title: 'Ask Sova',
        body:
            'Stuck? Ask Sova answers questions about how Sova works, in plain words, and explains '
            'a circle or a dispute from inside it. It\'s written by AI, so the circle screen stays the record.',
      ),
    TourStep(
      target: 'tab.1',
      title: 'Your circles',
      body: 'Open a circle to see the payout order, who has paid this turn, and the group rules.',
      before: () => router.go(SovaRoutes.circles),
    ),
    TourStep(
      target: 'tab.2',
      title: 'Activity',
      body: 'Every payment you\'ve sent or received, each with its receipt.',
      before: () => router.go(SovaRoutes.activity),
    ),
    TourStep(
      target: 'tab.3',
      title: 'Your record',
      body:
          'Your Sova Score grows as you pay on time. It\'s your record, not a credit rating. '
          'Your PIN, bank details and settings are here too.',
      before: () => router.go(SovaRoutes.record),
    ),
    TourStep(
      title: 'You\'re set',
      body:
          'Money actions always ask for your PIN, and every step goes into a tamper-evident record '
          'anyone in the circle can check. You can take this tour again from the Record tab.',
      before: () => router.go(SovaRoutes.home),
    ),
  ], onFinish: () => ref.read(authProvider.notifier).finishTour(Tour.home));
}

/// A short tour of a running circle, the first time one is opened.
void startCircleTour(BuildContext context, WidgetRef ref) {
  final assistant = ref.read(authProvider).session?.assistant ?? false;
  final steps = [
    const TourStep(
      target: 'circle.summary',
      title: 'This circle',
      body: 'What each person puts in, how often, and how many people are in it.',
    ),
    const TourStep(
      target: 'circle.turn',
      title: 'This turn',
      body:
          'Who collects now, and how many payments are confirmed. The collector receives one contribution '
          'from every other member.',
    ),
    const TourStep(
      target: 'circle.action',
      title: 'Your part',
      body:
          'Send your money to the collector by bank transfer or cash, then record it here with your PIN. '
          'When you collect, you confirm what arrived.',
    ),
    const TourStep(
      target: 'circle.order',
      title: 'Payout order',
      body: 'Drawn fairly once the circle filled up. "How it was drawn" lets you check it yourself.',
    ),
    if (assistant)
      const TourStep(
        target: 'circle.ask',
        title: 'Ask Sova',
        body: 'A plain-words summary of where this circle stands and what you should do next.',
      ),
    const TourStep(
      target: 'circle.verify',
      title: 'Check the record',
      body: 'Every payment, vote and turn goes into a tamper-evident record anyone can verify on the website.',
    ),
  ];
  showTour(
    context,
    // The circle screen builds every part up front, so parts this circle doesn't
    // have (no public record in the offline demo) are left out here.
    [for (final s in steps) if (s.target == null || TourTarget.contextOf(s.target!) != null) s],
    onFinish: () => ref.read(authProvider.notifier).finishTour(Tour.circle),
  );
}
