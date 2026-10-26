import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _length = 6;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _resendIn = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyOtp(code);
    } catch (e) {
      _controller.clear();
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final auth = ref.read(authProvider);
    final notifier = ref.read(authProvider.notifier);
    if (auth.pendingEmail case final email?) {
      await notifier.requestEmailCode(email);
    } else if (auth.pendingPhone case final phone?) {
      await notifier.requestOtp(phone);
    } else {
      return;
    }
    _startTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We sent you a new code.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final email = auth.pendingEmail;
    final code = _controller.text;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: email != null ? 'Change email' : 'Change number',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => ref.read(authProvider.notifier).changeNumber(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH, vertical: SovaSpacing.screenV),
          children: [
            Eyebrow(email != null ? 'Verify your email' : 'Verify your number'),
            const SizedBox(height: SovaSpacing.md),
            const Text('Enter the 6-digit code', style: SovaText.h1),
            const SizedBox(height: SovaSpacing.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  email != null
                      ? 'We emailed it to $email. Check your spam folder too. '
                      : 'We sent it by SMS to ${displayPhone(auth.pendingPhone ?? '')}. ',
                  style: SovaText.body,
                ),
                GestureDetector(
                  onTap: () => ref.read(authProvider.notifier).changeNumber(),
                  child: Text('Change', style: SovaText.label.copyWith(color: SovaColors.electric)),
                ),
              ],
            ),
            const SizedBox(height: SovaSpacing.xl3),
            // One hidden field drives six boxes, so paste and SMS autofill work.
            GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: Stack(
                children: [
                  Opacity(
                    opacity: 0,
                    // Keep the real field visible to screen readers.
                    alwaysIncludeSemantics: true,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_length)],
                      onChanged: (v) {
                        setState(() {});
                        if (v.length == _length) _verify(v);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < _length; i++)
                        Container(
                          width: 48,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: SovaColors.white,
                            borderRadius: BorderRadius.circular(SovaRadius.md),
                            border: Border.all(
                              color: i == code.length ? SovaColors.electric : SovaColors.borderStrong,
                              width: i == code.length ? 2 : 1,
                            ),
                          ),
                          child: Text(i < code.length ? code[i] : '', style: SovaText.h1),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SovaSpacing.lg),
            if (_busy) const LinearProgressIndicator(color: SovaColors.electric, backgroundColor: SovaColors.electricTint),
            if (_error != null) NoticeBox(_error!, icon: Icons.error_outline_rounded),
            const SizedBox(height: SovaSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: _resendIn > 0
                  ? Text('Resend code in ${_resendIn}s', style: SovaText.bodySmall)
                  : TextButton(onPressed: _resend, child: const Text('Resend code')),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            if (ref.read(repositoryProvider).otpHint case final hint?) NoticeBox(hint, icon: Icons.science_outlined),
          ],
        ),
      ),
    );
  }
}
