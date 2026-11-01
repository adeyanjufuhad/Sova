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

/// Signing in or signing up: an emailed code first, or Google, whichever the
/// backend has switched on. Phone codes come back with a paid SMS provider.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = normaliseEmail(_controller.text);
    if (email == null) {
      setState(() => _error = 'Enter your email address, like ada@example.com.');
      return;
    }
    await _run(() => ref.read(authProvider.notifier).requestEmailCode(email));
  }

  Future<void> _google(String idToken) => _run(() => ref.read(authProvider.notifier).signInWithGoogle(idToken));

  Future<void> _tryDemo() => _run(() => ref.read(authProvider.notifier).startDemo());

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

  /// The terms and privacy policy live on the website.
  void _open(String page) => launchUrl(Uri.parse('$siteUrl/$page/'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(signInMethodsProvider).value;
    // Only say email is off once the backend has answered.
    final emailOff = methods != null && !methods.email;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.screenV),
          children: [
            const SovaLogo(size: 28),
            const SizedBox(height: SovaSpacing.xl4),
            const Eyebrow('Sign up or sign in'),
            const SizedBox(height: SovaSpacing.md),
            const Text('What is your email?', style: SovaText.h1),
            const SizedBox(height: SovaSpacing.sm),
            const Text(
              'We will email you a 6-digit code. New to Sova? The same code creates your account.',
              style: SovaText.body,
            ),
            const SizedBox(height: SovaSpacing.xl3),
            TextField(
              controller: _controller,
              autofocus: !emailOff,
              enabled: !emailOff,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(254)],
              style: SovaText.h2,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'ada@example.com',
                errorText: _error,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.mail_outline_rounded),
              ),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            FilledButton(
              onPressed: _busy || emailOff ? null : _submit,
              child: _busy ? const SovaLoader(size: 22, color: SovaColors.white) : const Text('Send code'),
            ),
            if (emailOff) ...[
              const SizedBox(height: SovaSpacing.md),
              NoticeBox(
                methods.google
                    ? 'Email sign-up is coming soon. For now, continue with Google or try the demo.'
                    : 'Email sign-up is coming soon. For now, try the demo.',
                icon: Icons.schedule_rounded,
              ),
            ],
            if (methods?.googleClientId case final clientId?) ...[
              const SizedBox(height: SovaSpacing.lg),
              const _OrDivider(),
              const SizedBox(height: SovaSpacing.md),
              GoogleSignInButton(
                clientId: clientId,
                busy: _busy,
                onIdToken: _google,
                onError: (message) => setState(() => _error = message),
              ),
            ],
            if (emailOff && methods.demo)
              TextButton(onPressed: _busy ? null : _tryDemo, child: const Text('Try the demo')),
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
