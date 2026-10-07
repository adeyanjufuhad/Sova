import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';

void _done(BuildContext context, String message) {
  HapticFeedback.mediumImpact();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  leaveScreen(context, fallback: '/record');
}

/// The member's name, as the rest of their circles see it.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _name = TextEditingController(text: ref.read(authProvider).session?.fullName ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || !name.contains(' ')) {
      setState(() => _error = 'Enter your first and last name, as your circle knows you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).updateName(name);
      ref.invalidate(circlesProvider);
      if (mounted) _done(context, 'Name saved.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).session;
    final demo = session?.isDemo ?? false;
    return Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: '/record'), title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(SovaSpacing.screenH),
        children: [
          if (demo) ...[
            const NoticeBox(demoAccountNotice, icon: Icons.science_outlined),
            const SizedBox(height: SovaSpacing.lg),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: InputDecoration(labelText: 'Full name', errorText: _error),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: SovaSpacing.lg),
          InfoRow('Phone number', session == null ? '' : displayPhone(session.phone)),
          const Text(
            'Your number signs you in, so it can\'t be changed here.',
            style: SovaText.caption,
          ),
          const SizedBox(height: SovaSpacing.xl2),
          FilledButton(onPressed: _busy || demo ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}

/// Where members send this person's payout. Saving needs the PIN.
class BankDetailsScreen extends ConsumerStatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  ConsumerState<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends ConsumerState<BankDetailsScreen> {
  late final BankDetails? _current = ref.read(authProvider).session?.bank;
  late String? _bank = _current?.bankName;
  late final _number = TextEditingController(text: _current?.accountNumber ?? '');
  late final _name = TextEditingController(text: _current?.accountName ?? ref.read(authProvider).session?.fullName ?? '');
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final number = _number.text.replaceAll(RegExp(r'\s'), '');
    if (_bank == null) return setState(() => _error = 'Choose your bank.');
    if (!RegExp(r'^\d{10}$').hasMatch(number)) return setState(() => _error = 'Account numbers are 10 digits.');
    if (_name.text.trim().length < 2) return setState(() => _error = 'Enter the name on the account.');
    setState(() => _error = null);
    final bank = BankDetails(bankName: _bank!, accountNumber: number, accountName: _name.text.trim());
    final ok = await confirmWithPin(
      context,
      title: 'Save bank details',
      subtitle: 'Members will send your payout to ${bank.bankName} ${bank.accountNumber}.',
      onPin: (pin) => ref.read(authProvider.notifier).saveBank(bank, pin: pin),
    );
    if (!ok || !mounted) return;
    ref.invalidate(circlesProvider);
    _done(context, 'Bank details saved.');
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(_banksProvider);
    final demo = ref.watch(authProvider).session?.isDemo ?? false;
    return Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: '/record'), title: const Text('Bank details')),
      body: ListView(
        padding: const EdgeInsets.all(SovaSpacing.screenH),
        children: [
          if (demo) ...[
            const NoticeBox(demoAccountNotice, icon: Icons.science_outlined),
            const SizedBox(height: SovaSpacing.lg),
          ],
          const Text(
            'When it\'s your turn, members send your payout here. Sova never holds or moves money, so check '
            'every digit.',
            style: SovaText.bodySmall,
          ),
          const SizedBox(height: SovaSpacing.xl),
          banks.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => NoticeBox(e.toString()),
            data: (list) => DropdownMenu<String>(
              initialSelection: _bank,
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              label: const Text('Bank'),
              menuHeight: 320,
              onSelected: (v) => setState(() => _bank = v),
              dropdownMenuEntries: [for (final b in list) DropdownMenuEntry(value: b, label: b)],
            ),
          ),
          const SizedBox(height: SovaSpacing.lg),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: const InputDecoration(labelText: 'Account number', hintText: '10 digits'),
            style: SovaText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: SovaSpacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name on the account'),
          ),
          const SizedBox(height: SovaSpacing.sm),
          const Text(
            'Use the name your bank shows, so members can check it before they send.',
            style: SovaText.caption,
          ),
          if (_error != null) ...[
            const SizedBox(height: SovaSpacing.md),
            NoticeBox(_error!),
          ],
          const SizedBox(height: SovaSpacing.xl2),
          FilledButton(onPressed: demo ? null : _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

final _banksProvider = FutureProvider<List<String>>((ref) => ref.watch(repositoryProvider).banks());

/// Current PIN, then the new one twice.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

enum _PinStep { current, fresh, confirm }

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _pad = GlobalKey<PinPadState>();
  var _step = _PinStep.current;
  String? _current;
  String? _fresh;
  String? _error;
  bool _busy = false;

  Future<void> _entered(String pin) async {
    _pad.currentState?.clear();
    switch (_step) {
      case _PinStep.current:
        setState(() {
          _current = pin;
          _step = _PinStep.fresh;
          _error = null;
        });
      case _PinStep.fresh:
        if (isEasyPin(pin)) {
          setState(() => _error = 'That PIN is too easy to guess. Try another.');
        } else if (pin == _current) {
          setState(() => _error = 'Choose a PIN that\'s different from your current one.');
        } else {
          setState(() {
            _fresh = pin;
            _step = _PinStep.confirm;
            _error = null;
          });
        }
      case _PinStep.confirm:
        if (pin != _fresh) {
          setState(() {
            _step = _PinStep.fresh;
            _error = 'Those PINs didn\'t match. Enter your new PIN again.';
          });
          return;
        }
        setState(() => _busy = true);
        try {
          await ref.read(repositoryProvider).changePin(currentPin: _current!, newPin: pin);
          if (mounted) _done(context, 'PIN changed. Use your new PIN from now on.');
        } catch (e) {
          if (!mounted) return;
          // A wrong current PIN sends the member back to the start.
          setState(() {
            _busy = false;
            _step = _PinStep.current;
            _current = null;
            _fresh = null;
            _error = e.toString();
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, hint) = switch (_step) {
      _PinStep.current => ('Enter your current PIN', 'To keep your account safe.'),
      _PinStep.fresh => ('Choose a new PIN', 'Avoid easy ones like 1234 or 1111.'),
      _PinStep.confirm => ('Enter the new PIN again', 'To make sure it\'s right.'),
    };
    if (ref.watch(authProvider).session?.isDemo ?? false) {
      return Scaffold(
        appBar: AppBar(leading: const SovaBackButton(fallback: '/record'), title: const Text('Change PIN')),
        body: ListView(
          padding: const EdgeInsets.all(SovaSpacing.screenH),
          children: const [NoticeBox(demoAccountNotice, icon: Icons.science_outlined)],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(leading: const SovaBackButton(fallback: '/record'), title: const Text('Change PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SovaSpacing.screenH),
          children: [
            const SizedBox(height: SovaSpacing.lg),
            const Icon(Icons.lock_outline_rounded, color: SovaColors.electric, size: 32),
            const SizedBox(height: SovaSpacing.md),
            Text(title, style: SovaText.h2, textAlign: TextAlign.center),
            const SizedBox(height: SovaSpacing.xs),
            Text(hint, style: SovaText.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: SovaSpacing.xl2),
            PinPad(key: _pad, busy: _busy, onCompleted: _entered),
            if (_error != null) ...[
              const SizedBox(height: SovaSpacing.lg),
              NoticeBox(_error!),
            ],
          ],
        ),
      ),
    );
  }
}
