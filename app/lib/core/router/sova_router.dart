import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../theme/theme.dart';
import '../../features/activity/activity_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/circle/circle_screen.dart';
import '../../features/circle/disputes_screen.dart';
import '../../features/circle/draw_screen.dart';
import '../../features/circle/pay_screen.dart';
import '../../features/circle/payout_screen.dart';
import '../../features/circle/receipt_screen.dart';
import '../../features/circle/rules_screen.dart';
import '../../features/circles/circles_screen.dart';
import '../../features/create/create_circle_screen.dart';
import '../../features/join/join_circle_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/record/record_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/common.dart';

abstract final class SovaRoutes {
  static const start = '/';
  static const welcome = '/welcome';
  static const phone = '/phone';
  static const otp = '/otp';
  static const profile = '/profile';
  static const home = '/home';
  static const circles = '/circles';
  static const activity = '/activity';
  static const record = '/record';
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever sign-in state changes.
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: SovaRoutes.start,
    // A friendly page for links that point nowhere (old, mistyped or shortened).
    errorBuilder: (context, _) => Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: SovaRoutes.home), title: const Text('Page not found')),
      body: Padding(
        padding: const EdgeInsets.all(SovaSpacing.screenH),
        child: Center(
          child: EmptyState(
            icon: Icons.link_off_rounded,
            title: 'This page doesn\'t exist',
            message: 'The link may be old or mistyped. Your circles and payments are safe.',
            action: FilledButton(onPressed: () => context.go(SovaRoutes.home), child: const Text('Go to home')),
          ),
        ),
      ),
    ),
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final at = state.matchedLocation;

      // Where this person should be, given how far through sign-up they are.
      final String? gate;
      if (auth.restoring) {
        gate = SovaRoutes.start;
      } else if (!auth.onboarded) {
        gate = SovaRoutes.welcome;
      } else if (!auth.signedIn) {
        gate = auth.pendingPhone == null ? SovaRoutes.phone : SovaRoutes.otp;
      } else if (!auth.ready) {
        gate = SovaRoutes.profile;
      } else {
        gate = null;
      }

      if (gate != null) return at == gate ? null : gate;

      // Fully signed in: keep people out of the sign-up screens.
      const authScreens = {SovaRoutes.start, SovaRoutes.welcome, SovaRoutes.phone, SovaRoutes.otp, SovaRoutes.profile};
      return authScreens.contains(at) ? SovaRoutes.home : null;
    },
    routes: [
      // Shown for a moment while the saved session loads.
      GoRoute(path: SovaRoutes.start, builder: (_, _) => const Scaffold(body: LoadingView())),
      GoRoute(path: SovaRoutes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: SovaRoutes.phone, builder: (_, _) => const PhoneScreen()),
      GoRoute(path: SovaRoutes.otp, builder: (_, _) => const OtpScreen()),
      GoRoute(path: SovaRoutes.profile, builder: (_, _) => const ProfileScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: SovaRoutes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: SovaRoutes.circles, builder: (_, _) => const CirclesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: SovaRoutes.activity, builder: (_, _) => const ActivityScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: SovaRoutes.record, builder: (_, _) => const RecordScreen())]),
        ],
      ),
      // Full-screen flows above the tab bar.
      GoRoute(path: '/create', parentNavigatorKey: _rootKey, builder: (_, _) => const CreateCircleScreen()),
      GoRoute(path: '/join', parentNavigatorKey: _rootKey, builder: (_, _) => const JoinCircleScreen()),
      GoRoute(
        path: '/circle/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => CircleScreen(circleId: state.pathParameters['id']!),
        routes: [
          GoRoute(path: 'pay', builder: (_, state) => PayScreen(circleId: state.pathParameters['id']!)),
          GoRoute(path: 'rules', builder: (_, state) => RulesScreen(circleId: state.pathParameters['id']!)),
          GoRoute(path: 'payout', builder: (_, state) => PayoutScreen(circleId: state.pathParameters['id']!)),
          GoRoute(path: 'draw', builder: (_, state) => DrawScreen(circleId: state.pathParameters['id']!)),
          GoRoute(
            path: 'disputes',
            builder: (_, state) => DisputesScreen(circleId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: ':disputeId',
                builder: (_, state) => DisputeScreen(
                  circleId: state.pathParameters['id']!,
                  disputeId: state.pathParameters['disputeId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'receipt/:roundId',
            builder: (_, state) => ReceiptScreen(
              circleId: state.pathParameters['id']!,
              roundId: state.pathParameters['roundId']!,
            ),
          ),
        ],
      ),
    ],
  );
});
