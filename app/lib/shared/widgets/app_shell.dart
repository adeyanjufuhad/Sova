import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';

/// Bottom tab bar around the four main tabs. Each tab keeps its own
/// navigation stack and scroll position.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Circles'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Record'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      // A floating pill: inset from the edges, hairline border, no shadow.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(SovaSpacing.lg, 0, SovaSpacing.lg, SovaSpacing.md),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: SovaColors.white,
            borderRadius: BorderRadius.circular(SovaRadius.full),
            border: Border.all(color: SovaColors.borderStrong),
          ),
          child: NavigationBar(
            height: 64,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
              // Tapping the current tab again returns it to its first screen.
              shell.goBranch(i, initialLocation: i == shell.currentIndex);
            },
            destinations: [
              for (final (icon, selected, label) in _tabs)
                NavigationDestination(
                  icon: Icon(icon, color: SovaColors.textMuted),
                  selectedIcon: Icon(selected, color: SovaColors.electric),
                  label: label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
