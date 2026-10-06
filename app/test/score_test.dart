import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sova/core/theme/sova_theme.dart';
import 'package:sova/data/api/api_client.dart';
import 'package:sova/data/api/api_repository.dart';
import 'package:sova/data/api/session_store.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/data/sova_repository.dart';
import 'package:sova/features/record/score_card.dart';

void main() {
  test('the demo score follows the database formula', () async {
    final repo = DemoRepository();
    await repo.startDemo();
    final s = await repo.myScore();
    // Seeded payments: 2 confirmed in Office Esusu, 1 in the class ajo (turn 1).
    expect(s.confirmedPayments, 3);
    expect(s.ready, isTrue);
    expect(s.score, (100 * (0.6 * s.onTimeRate + 0.25 * s.consistencyRate + 0.15 * s.completionRate)).round());
    expect(s.band, DemoRepository.scoreBand(s.score!));
    // Office Esusu's turn 3 isn't due yet, so owing it doesn't count against you.
    expect(s.consistencyRate, 1);
    expect(s.completionRate, 0); // no finished circles in the demo
    expect(() => repo.shareScore(pin: DemoRepository.demoPin), throwsA(isA<SovaException>()));
  });

  test('score bands', () {
    expect([90, 89, 75, 74, 50, 49].map(DemoRepository.scoreBand), ['Excellent', 'Strong', 'Strong', 'Fair', 'Fair', 'Building']);
    expect(shortName('Ada Obi'), 'Ada O.');
    expect(shortName('Kemi'), 'Kemi');
    expect(shortName(null), 'Member');
  });

  test('maps a score and its live link from the API', () async {
    final body = {
      'minimumPayments': 3,
      'ready': true,
      'score': 86,
      'band': 'Strong',
      'onTimeRate': 0.9,
      'consistencyRate': 1,
      'completionRate': 0.5,
      'confirmedPayments': 20,
      'onTimePayments': 18,
      'turnsCounted': 20,
      'activeCircles': 2,
      'completedCircles': 2,
      'share': {'token': 'abcdefghijklmnopqrstuvwx', 'sharedAt': '2026-10-06T10:00:00Z', 'score': 84},
    };
    final repo = ApiRepository(
      ApiClient(
        baseUrl: 'https://api.test',
        store: MemorySessionStore(),
        client: MockClient((_) async =>
            http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'})),
        wakeRetryDelay: Duration.zero,
      ),
    );
    final s = await repo.myScore();
    expect((s.score, s.band, s.consistencyRate, s.completedCircles), (86, 'Strong', 1.0, 2));
    expect(s.share!.score, 84);
    expect(scoreLink(s.share!.token), endsWith('/score/?t=abcdefghijklmnopqrstuvwx'));
  });

  Future<void> pumpCard(WidgetTester tester, SovaRepository repo) async {
    tester.view.physicalSize = const Size(412, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: SovaTheme.light,
        home: const Scaffold(body: SingleChildScrollView(child: ScoreCard(footer: SizedBox.shrink()))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the card shows the score, its parts, and what sharing reveals', (tester) async {
    final repo = DemoRepository();
    await tester.runAsync(repo.startDemo);
    await pumpCard(tester, repo);

    expect(find.text('Sova Score'), findsOneWidget);
    expect(find.text('/ 100'), findsOneWidget);
    expect(find.text('Paid on time'), findsOneWidget);
    expect(find.text('60% of score'), findsOneWidget);
    expect(find.textContaining('not a credit rating'), findsOneWidget);

    await tester.tap(find.text('Share my score'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Never shown: your phone number'), findsOneWidget);
    expect(find.text('Create a private link'), findsOneWidget);
  });

  testWidgets('a newcomer sees progress towards a first score, not a low number', (tester) async {
    final repo = _Newcomer();
    await pumpCard(tester, repo);
    expect(find.text('Your score starts after 3 confirmed payments'), findsOneWidget);
    expect(find.textContaining('1 of 3 so far'), findsOneWidget);
    expect(find.text('Share my score'), findsNothing);
  });
}

class _Newcomer extends DemoRepository {
  @override
  Future<SovaScore> myScore() async => const SovaScore(
        minimumPayments: 3,
        score: null,
        band: null,
        onTimeRate: 1,
        consistencyRate: 1,
        completionRate: 0,
        confirmedPayments: 1,
        onTimePayments: 1,
        activeCircles: 1,
        completedCircles: 0,
      );
}
