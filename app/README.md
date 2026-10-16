# Sova app

The Sova app for members of savings circles: Flutter for Android and the web, package `ng.sova.app`. The web build is live at https://sova-app.rumptycloud.app.

## Run

```bash
flutter pub get
flutter run -d chrome --web-port 3300 --dart-define=SOVA_API_URL=http://localhost:8080
```

Use `flutter run` on an Android phone or emulator instead of `-d chrome`; an emulator reaches your computer's API at `http://10.0.2.2:8080`. To use the live API, pass `--dart-define=SOVA_API_URL=https://sova-api.rumptycloud.app` (the API must list your origin in `CORS_ORIGINS` for web runs).

Without `SOVA_API_URL` the app runs on the in-memory demo backend: no server needed, one-time code `123456`, PIN `2580`.

| Build-time define | Default | Purpose |
|---|---|---|
| `SOVA_API_URL` | none (demo backend) | The Sova API |
| `SOVA_SITE_URL` | `https://sova.rumptycloud.app` | Website, for "Verify this circle" and shared score links |

## Checks

```bash
flutter analyze
flutter test
```

The tests use the demo backend and include a layout test that opens the main screens at 320 and 412 px wide with 130% text and names any screen that overflows.

## Structure

```
lib/
  main.dart, app.dart     start-up, theme, router
  core/
    theme/                tokens, text styles, Material theme (see ../DESIGN.md)
    router/               GoRouter routes and the sign-in redirect
    format.dart           naira (₦120,000), dates, Nigerian phones (+234…)
  data/
    sova_repository.dart  the interface every screen uses
    api/                  ApiRepository + ApiClient (tokens, refresh, wake-up retries, errors)
    demo_repository.dart  in-memory backend with the same rules, for tests and offline runs
    fair_draw.dart        the commit-reveal draw in Dart, to recheck draws on the phone
    models.dart, providers.dart, insights.dart
  features/               one folder per area: auth, home, circles, circle, create, join,
                          activity, record, notifications, settings
  shared/widgets/         PIN pad and sheet, liquid-glass tab bar, adire painter, common pieces
```

Screens never call HTTP: they talk to `SovaRepository` through Riverpod providers, so the demo backend can stand in for the API.

## Sessions

The access token stays in memory. The refresh token is kept in secure storage on Android and in the tab's `sessionStorage` on the web (it survives a reload and ends when the tab closes).

## Web hosting

`.github/workflows/app-web.yml` tests and builds the web app on every push to `main` that touches `app/`, then publishes `build/web` to the `app-web` branch, which RumptyCloud serves as a static site. RumptyCloud's builder has no Flutter SDK, which is why GitHub Actions builds it.

To preview a local release build: `flutter build web`, then `python tool/serve_web.py` (port 3300, or `$PORT`).

## Android

`.github/workflows/android-apk.yml` tests the app and builds a release APK against the live API (`SOVA_API_URL`, `SITE_URL` repository variables, falling back to the live addresses). Push a tag such as `v1.0.0` to publish the APK on a GitHub Release; running the workflow by hand keeps the APK as a workflow artifact for 14 days.

Release signing comes from `android/key.properties` (git-ignored). In CI it is written from four repository secrets:

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The upload keystore (`.jks`), base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Its store password |
| `ANDROID_KEY_ALIAS` | The key's alias |
| `ANDROID_KEY_PASSWORD` | The key's password |

Create a keystore once with `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload` and keep it safe: Google Play needs the same key for every update. Without these secrets the APK is signed with a throwaway debug key, which installs fine but can't be updated in place by a later signed build.
