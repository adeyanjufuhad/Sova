import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../features/tour/tours.dart';
import 'glass_tab_bar.dart';
import 'tour.dart';

/// The four main tabs under a floating glass tab bar. Each tab keeps its own
/// navigation stack and scroll position. Content scrolls behind the bar (so
/// the glass has something to blur); tab screens pad their lists with
/// [tabBarInset] so nothing stays hidden under it.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _tour = TourLauncher();

  static const _tabs = [
    GlassTab(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
    GlassTab(icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Circles'),
    GlassTab(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Activity'),
    GlassTab(icon: Icons.insights_outlined, selectedIcon: Icons.insights_rounded, label: 'Record'),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    // New accounts and every private demo get the main tour once.
    _tour.maybeStart(
      ref.watch(authProvider.select((s) => s.session?.pendingTours.contains(Tour.home) ?? false)),
      () => startHomeTour(context, ref),
    );
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(SovaSpacing.lg, 0, SovaSpacing.lg, SovaSpacing.md),
        child: GlassTabBar(
          tabs: _tabs,
          currentIndex: shell.currentIndex,
          // Choosing the current tab again returns it to its first screen.
          onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        ),
      ),
    );
  }
}

/// Space to leave at the end of a tab's list so its last item clears the tab bar.
double tabBarInset(BuildContext context) => MediaQuery.paddingOf(context).bottom;
