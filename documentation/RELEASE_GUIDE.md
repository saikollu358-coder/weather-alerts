# Release Guide

End-to-end steps to ship a `weather_alerts` build. Follows the `AGENTS.md`
release gate.

## Android application id

- Internal namespace: `com.weatheralerts.weather_alerts` (R class, Kotlin).
- Public install/store id: `com.weatheralerts.app` (`applicationId`).
- Firebase is configured from the platform config file
  `android/app/google-services.json`. The google-services Gradle plugin is
  applied automatically only when that file exists, so local-only builds
  (no Firebase) keep working. The Android app id in `google-services.json`
  must match `com.weatheralerts.app`. See `documentation/FIREBASE_SETUP.md`.

## Release signing

Release builds require a keystore. Keys are **never committed**:

1. Generate a keystore (keep it outside the repo):
   `keytool -genkey -v -keystore weather_alerts-release.jks -alias weather_alerts -keyalg RSA -keysize 2048 -validity 10000`
2. Copy `android/key.properties.example` to `android/key.properties` and fill
   in `storeFile`, `storePassword`, `keyAlias`, `keyPassword` (paths are
   relative to `android/`).
3. `android/key.properties` and `*.jks` are gitignored.

If `key.properties` is absent, `flutter build apk --release` still succeeds but
signs with the **debug** key — usable for CI/testing but **not** store-publishable.

## Release gate

```sh
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web
```

After the gate, publish `app-release.apk` (signed) and the `build/web/` bundle.
Verify the APK was signed with the release key:

```sh
# expected output contains a Signature scheme line (v1/v2/v3)
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## Versioning

`pubspec.yaml` holds `version: 1.0.0+1`. Bump it per release; override on demand
with `--build-name` / `--build-number`.