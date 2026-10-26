import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/sova_loader.dart';
import 'google_sign_in_button.dart';

/// Signing in: a phone number by default, or an email address, or Google,
/// whichever the backend has switched on.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _useEmail = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authProvider.notifier);
    final address = _useEmail ? normaliseEmail(_controller.text) : normalisePhone(_controller.text);
    if (address == null) {
      setState(() => _error =
          _useEmail ? 'Enter your email address, like ada@example.com.' : 'Enter a Nigerian mobile number, like 0803 123 4567.');
      return;
    }
    await _run(() => _useEmail ? auth.requestEmailCode(address) : auth.requestOtp(address));
  }

  Future<void> _google(String idToken) => _run(() => ref.read(authProvider.notifier).signInWithGoogle(idToken));

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() => setState(() {
        _useEmail = !_useEmail;
        _controller.clear();
        _error = null;
      });

  /// The terms and privacy policy live on the website.
  void _open(String page) => launchUrl(Uri.parse('$siteUrl/$page/'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(signInMethodsProvider).value;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.screenV),
          children: [
            const SovaLogo(size: 28),
            const SizedBox(height: SovaSpacing.xl4),
            const Eyebrow('Sign in'),
            const SizedBox(height: SovaSpacing.md),
            Text(_useEmail ? 'What is your email?' : 'What is your phone number?', style: SovaText.h1),
            const SizedBox(height: SovaSpacing.sm),
            Text(
              _useEmail
                  ? 'We will email you a 6-digit code to confirm it is you.'
                  : 'We will text you a 6-digit code to confirm it is you.',
              style: SovaText.body,
            ),
            const SizedBox(height: SovaSpacing.xl3),
            TextField(
              key: ValueKey(_useEmail),
              controller: _controller,
              autofocus: true,
              keyboardType: _useEmail ? TextInputType.emailAddress : TextInputType.phone,
              autocorrect: false,
              autofillHints: [_useEmail ? AutofillHints.email : AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.done,
              inputFormatters: _useEmail
                  ? [LengthLimitingTextInputFormatter(254)]
                  : [FilteringTextInputFormatter.allow(RegExp(r'[\d\s+]')), LengthLimitingTextInputFormatter(16)],
              style: SovaText.h2,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: _useEmail ? 'ada@example.com' : '0803 123 4567',
                errorText: _error,
                errorMaxLines: 3,
                prefixIcon: _useEmail
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: SovaSpacing.lg, right: SovaSpacing.sm),
                        child: Text('+234', style: SovaText.h3.copyWith(height: 2.1)),
                      ),
              ),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const SovaLoader(size: 22, color: SovaColors.white) : const Text('Send code'),
            ),
            if (methods?.email ?? false)
              TextButton(
                onPressed: _busy ? null : _switchMode,
                child: Text(_useEmail ? 'Use my phone number instead' : 'Use email instead'),
              ),
            if (methods?.googleClientId case final clientId?) ...[
              const SizedBox(height: SovaSpacing.sm),
              const _OrDivider(),
              const SizedBox(height: SovaSpacing.md),
              GoogleSignInButton(
                clientId: clientId,
                busy: _busy,
                onIdToken: _google,
                onError: (message) => setState(() => _error = message),
              ),
            ],
            const SizedBox(height: SovaSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('By continuing you agree to the', style: SovaText.bodySmall),
                TextButton(onPressed: () => _open('terms'), child: const Text('Terms')),
                const Text('and', style: SovaText.bodySmall),
                TextButton(onPressed: () => _open('privacy'), child: const Text('Privacy policy')),
              ],
            ),
            const SizedBox(height: SovaSpacing.lg),
            const NoticeBox(
              'Sova will never call, text or email to ask for your PIN or this code. Never share them with anyone.',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: SovaSpacing.md),
          child: Text('or', style: SovaText.bodySmall),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}
