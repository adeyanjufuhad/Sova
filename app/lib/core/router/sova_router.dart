import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/circle/circle_screen.dart';
import '../../features/circle/pay_screen.dart';
import '../../features/circle/receipt_screen.dart';
import '../../features/circle/rules_screen.dart';
import '../../features/home/home_screen.dart';

abstract final class SovaRoutes {
  static const welcome = '/welcome';
  static const phone = '/phone';
  static const otp = '/otp';
  static const profile = '/profile';
  static const home = '/home';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever sign-in state changes.
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: SovaRoutes.welcome,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final at = state.matchedLocation;

      // Where this person should be, given how far through sign-up they are.
      final String? gate;
      if (!auth.onboarded) {
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
      const authScreens = {SovaRoutes.welcome, SovaRoutes.phone, SovaRoutes.otp, SovaRoutes.profile};
      return authScreens.contains(at) ? SovaRoutes.home : null;
    },
    routes: [
      GoRoute(path: SovaRoutes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: SovaRoutes.phone, builder: (_, _) => const PhoneScreen()),
      GoRoute(path: SovaRoutes.otp, builder: (_, _) => const OtpScreen()),
      GoRoute(path: SovaRoutes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: SovaRoutes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/circle/:id',
        builder: (_, state) => CircleScreen(circleId: state.pathParameters['id']!),
        routes: [
          GoRoute(path: 'pay', builder: (_, state) => PayScreen(circleId: state.pathParameters['id']!)),
          GoRoute(path: 'rules', builder: (_, state) => RulesScreen(circleId: state.pathParameters['id']!)),
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
