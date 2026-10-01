import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = normalisePhone(_controller.text);
    if (phone == null) {
      setState(() => _error = 'Enter a Nigerian mobile number, like 0803 123 4567.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).requestOtp(phone);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.screenV),
          children: [
            const SovaLogo(size: 28),
            const SizedBox(height: SovaSpacing.xl4),
            const Eyebrow('Sign in'),
            const SizedBox(height: SovaSpacing.md),
            const Text('What is your phone number?', style: SovaText.h1),
            const SizedBox(height: SovaSpacing.sm),
            const Text('We will text you a 6-digit code to confirm it is you.', style: SovaText.body),
            const SizedBox(height: SovaSpacing.xl3),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s+]')), LengthLimitingTextInputFormatter(16)],
              style: SovaText.h2,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '0803 123 4567',
                errorText: _error,
                errorMaxLines: 2,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: SovaSpacing.lg, right: SovaSpacing.sm),
                  child: Text('+234', style: SovaText.h3.copyWith(height: 2.1)),
                ),
              ),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: SovaColors.white))
                  : const Text('Send code'),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            const NoticeBox(
              'Sova will never call or text to ask for your PIN or this code. Never share them with anyone.',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
