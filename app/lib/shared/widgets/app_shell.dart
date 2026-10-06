import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import 'glass_tab_bar.dart';

/// The four main tabs under a floating glass tab bar. Each tab keeps its own
/// navigation stack and scroll position. Content scrolls behind the bar (so
/// the glass has something to blur); tab screens pad their lists with
/// [tabBarInset] so nothing stays hidden under it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    GlassTab(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
    GlassTab(icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Circles'),
    GlassTab(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Activity'),
    GlassTab(icon: Icons.insights_outlined, selectedIcon: Icons.insights_rounded, label: 'Record'),
  ];

  @override
  Widget build(BuildContext context) {
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
