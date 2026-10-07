import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sova/app.dart';
import 'package:sova/core/router/sova_router.dart';
import 'package:sova/data/demo_repository.dart';
import 'package:sova/data/models.dart';
import 'package:sova/data/providers.dart';
import 'package:sova/data/sova_repository.dart';

const pin = DemoRepository.demoPin;

class _SignedIn extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        restoring: false,
        onboarded: true,
        session: Session(phone: '+2348000000000', userId: 'me', fullName: 'Ada Obi', hasPin: true),
      );
}

void main() {
  late DemoRepository repo;

  setUp(() async {
    repo = DemoRepository();
    await repo.startDemo();
  });

  group('settings', () {
    test('a new name shows in every circle', () async {
      final s = await repo.updateName('Adaeze Obi');
      expect(s.fullName, 'Adaeze Obi');
      for (final c in await repo.myCircles()) {
        expect(c.memberById('me')!.name, 'Adaeze Obi');
      }
    });

    test('bank details need the PIN and a 10-digit account number', () async {
      const bank = BankDetails(bankName: 'OPay', accountNumber: '9061234567', accountName: 'Ada Obi');
      await expectLater(repo.saveBank(bank: bank, pin: '0000'), throwsA(isA<SovaException>()));
      await expectLater(
        repo.saveBank(bank: const BankDetails(bankName: 'OPay', accountNumber: '906123', accountName: 'Ada Obi'), pin: pin),
        throwsA(isA<SovaException>()),
      );
      final s = await repo.saveBank(bank: bank, pin: pin);
      expect(s.bank!.accountNumber, '9061234567');
      expect((await repo.circle('office-esusu')).memberById('me')!.bank!.bankName, 'OPay');
    });

    test('the PIN changes only with the current one, and not to an easy one', () async {
      await expectLater(repo.changePin(currentPin: '0000', newPin: '4826'), throwsA(isA<SovaException>()));
      await expectLater(
        repo.changePin(currentPin: pin, newPin: '1111'),
        throwsA(isA<SovaException>().having((e) => e.code, 'code', 'weak_pin')),
      );
      await repo.changePin(currentPin: pin, newPin: '4826');
      await repo.verifyPin('4826');
      await expectLater(repo.verifyPin(pin), throwsA(isA<SovaException>()));
    });
  });

  test('the inbox reminds what is due and what to confirm, and clears when read', () async {
    final inbox = await repo.notifications();
    expect(inbox.reminders.map((r) => r.kind), containsAll(['due', 'confirm']));
    final due = inbox.reminders.firstWhere((r) => r.kind == 'due');
    expect(due.title, 'Pay Halima ₦20,000');
    expect(due.link, '/circle/office-esusu/pay');
    expect(inbox.badge, inbox.reminders.length + 2); // two unread notifications

    await repo.markNotificationsRead();
    expect((await repo.notifications()).badge, inbox.reminders.length);
  });

  testWidgets('a member changes their PIN from settings', (tester) async {
    final demo = DemoRepository();
    await tester.runAsync(demo.startDemo);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(_SignedIn.new),
      repositoryProvider.overrideWithValue(demo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SovaApp()));
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/settings/pin');
    await tester.pumpAndSettle();

    Future<void> enter(String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    expect(find.text('Enter your current PIN'), findsOneWidget);
    await enter(pin);
    await enter('1234');
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    await enter('4826');
    expect(find.text('Enter the new PIN again'), findsOneWidget);
    await enter('4826');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('PIN changed'), findsOneWidget);
    await tester.runAsync(() => demo.verifyPin('4826'));
  });
}
