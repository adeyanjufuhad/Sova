import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google's own "Continue with Google" button, as its web sign-in requires.
Widget renderGoogleButton() => web.renderButton(
      configuration: web.GSIButtonConfiguration(
        type: web.GSIButtonType.standard,
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        text: web.GSIButtonText.continueWith,
        shape: web.GSIButtonShape.pill,
        logoAlignment: web.GSIButtonLogoAlignment.center,
        minimumWidth: 280,
      ),
    );
