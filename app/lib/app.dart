import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/sova_router.dart';
import 'core/theme/theme.dart';

class SovaApp extends ConsumerWidget {
  const SovaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Sova',
      debugShowCheckedModeBanner: false,
      theme: SovaTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
