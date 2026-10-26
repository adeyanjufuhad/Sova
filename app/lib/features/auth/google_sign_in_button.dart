import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart' as platform;

/// "Continue with Google". On the web Google draws its own button (its rules);
/// on Android ours opens Google's account picker. Either way the ID token goes
/// to [onIdToken], and the API checks it with Google.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.clientId, required this.onIdToken, required this.onError, this.busy = false});

  /// The web OAuth client id. Android asks Google for a token meant for it.
  final String clientId;
  final ValueChanged<String> onIdToken;
  final ValueChanged<String> onError;
  final bool busy;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  /// GoogleSignIn may only be initialised once per app run.
  static Future<void>? _initialised;

  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool _ready = false;

  static const _failed = 'Google sign-in didn\'t work. Please try again, or use your phone or email.';

  @override
  void initState() {
    super.initState();
    _initialised ??= GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? widget.clientId : null,
      serverClientId: kIsWeb ? null : widget.clientId,
    );
    _initialised!.then(
      (_) {
        if (!mounted) return;
        // On the web the token only arrives as an event from Google's button.
        if (kIsWeb) _events = GoogleSignIn.instance.authenticationEvents.listen(_onEvent, onError: _onError);
        setState(() => _ready = true);
      },
      onError: (Object _) {
        _initialised = null;
        if (mounted) widget.onError('Google sign-in isn\'t available right now. Use your phone or email.');
      },
    );
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) _deliver(event.user);
  }

  void _onError(Object error) {
    if (error is GoogleSignInException && error.code == GoogleSignInExceptionCode.canceled) return;
    widget.onError(_failed);
  }

  void _deliver(GoogleSignInAccount account) {
    final token = account.authentication.idToken;
    if (token == null) {
      widget.onError(_failed);
    } else {
      widget.onIdToken(token);
    }
  }

  Future<void> _tap() async {
    try {
      _deliver(await GoogleSignIn.instance.authenticate());
    } on GoogleSignInException catch (e) {
      _onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(height: 44, child: _ready ? Center(child: platform.renderGoogleButton()) : null);
    }
    return OutlinedButton.icon(
      onPressed: _ready && !widget.busy ? _tap : null,
      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
      label: const Text('Continue with Google'),
    );
  }
}
