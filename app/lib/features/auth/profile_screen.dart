import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';

enum _Step { name, pin, confirmPin }

/// Name, then a 4-digit PIN entered twice. The PIN protects every
/// money-related action in the app.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _padKey = GlobalKey<PinPadState>();
  _Step _step = _Step.name;
  String _firstPin = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submitName() {
    final name = _name.text.trim();
    if (name.length < 2 || !name.contains(' ')) {
      setState(() => _error = 'Enter your first and last name, as your group knows you.');
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.pin;
    });
  }

  Future<void> _onPin(String pin) async {
    if (_step == _Step.pin) {
      if (isEasyPin(pin)) {
        _padKey.currentState?.clear();
        setState(() => _error = 'That PIN is too easy to guess. Try another.');
        return;
      }
      _padKey.currentState?.clear();
      setState(() {
        _firstPin = pin;
        _error = null;
        _step = _Step.confirmPin;
      });
      return;
    }

    if (pin != _firstPin) {
      _padKey.currentState?.clear();
      setState(() {
        _error = 'The PINs did not match. Choose your PIN again.';
        _firstPin = '';
        _step = _Step.pin;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).saveProfile(fullName: _name.text.trim(), pin: pin);
    } catch (e) {
      _padKey.currentState?.clear();
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _step == _Step.name
          ? null
          : AppBar(
              leading: BackButton(
                onPressed: () => setState(() {
                  _error = null;
                  _step = _Step.name;
                }),
              ),
            ),
      body: SafeArea(
        child: _step == _Step.name ? _nameStep() : _pinStep(),
      ),
    );
  }

  Widget _nameStep() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.screenV),
      children: [
        const Eyebrow('Step 1 of 2'),
        const SizedBox(height: SovaSpacing.md),
        const Text('What should your group call you?', style: SovaText.h1),
        const SizedBox(height: SovaSpacing.sm),
        const Text('Use the name your circle knows. It appears on receipts.', style: SovaText.body),
        const SizedBox(height: SovaSpacing.xl3),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _submitName(),
          decoration: InputDecoration(labelText: 'Full name', hintText: 'Adaeze Okafor', errorText: _error),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        FilledButton(onPressed: _submitName, child: const Text('Continue')),
      ],
    );
  }

  Widget _pinStep() {
    final confirming = _step == _Step.confirmPin;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.lg),
      children: [
        const Eyebrow('Step 2 of 2'),
        const SizedBox(height: SovaSpacing.md),
        Text(confirming ? 'Enter your PIN again' : 'Create a 4-digit PIN', style: SovaText.h1),
        const SizedBox(height: SovaSpacing.sm),
        const Text('You will use it to confirm payments. Never share it, not even with Sova.', style: SovaText.body),
        const SizedBox(height: SovaSpacing.xl3),
        PinPad(key: _padKey, busy: _busy, onCompleted: _onPin),
        if (_error != null) ...[
          const SizedBox(height: SovaSpacing.lg),
          NoticeBox(_error!, icon: Icons.error_outline_rounded),
        ],
      ],
    );
  }
}
