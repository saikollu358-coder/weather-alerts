# Firebase Setup

How to connect this app to a Firebase project for registration, login and
cloud sync. Config **never lives in the repo**: it enters through platform
config files (`google-services.json`) or `--dart-define`.

Until configuration is present the app runs in **local-only mode** (offline
first): sign-in/registration show a friendly "cloud sign-in requires Firebase
configuration" error.

## Prerequisites (Firebase console)

1. Create a Firebase project (or reuse one) at
   https://console.firebase.google.com.
2. **Authentication → Sign-in method → Email/Password** → enable.
3. Enable **Cloud Firestore** (production mode).
4. Deploy `firestore.rules` (already in the repo) to make `users/{uid}`
   owner-only and keep server data read-only:
   ```
   firebase deploy --only firestore:rules
   ```

## Android (recommended)

1. In the Firebase console register an **Android app** whose package name
   matches the app's `applicationId`:
   ```
   com.weatheralerts.app
   ```
   (Mismatch => the google-services plugin fails the build.)

2. Download **google-services.json** and place it at
   ```
   android/app/google-services.json
   ```
   It is gitignored — never commit it.

3. The Gradle wiring is already in place:
   `android/app/build.gradle.kts` applies `com.google.gms.google-services`
   only when `google-services.json` exists, so builds keep working without it.

4. Build / run:
   ```sh
   flutter pub get
   flutter run
   flutter build apk --release
   ```

## Web (optional)

Build with the six `FIREBASE_WEB_*` defines from the Firebase console
(Project settings → Your apps → Web app):

```sh
flutter run -d chrome \
  --dart-define=FIREBASE_WEB_API_KEY=your_api_key \
  --dart-define=FIREBASE_WEB_AUTH_DOMAIN=your_project.firebaseapp.com \
  --dart-define=FIREBASE_WEB_PROJECT_ID=your_project \
  --dart-define=FIREBASE_WEB_STORAGE_BUCKET=your_project.appspot.com \
  --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID=1234567890 \
  --dart-define=FIREBASE_WEB_APP_ID=1:1234567890:web:abcdef
```

`AppConfig.firebaseWebOptions` (`lib/core/config/app_config.dart`) assembles
these into `FirebaseOptions`.

## Where the code hooks in

- `lib/services/firebase/firebase_service.dart` — initialization + the
  availability flag used by every Firebase service.
- `lib/services/firebase/auth_service.dart` — Firebase Auth register/login
  (register stores the chosen **username** as the auth display name).
- `lib/data/repositories/auth_repository_impl.dart` — after registration writes
  `users/{uid}/profile/default` with `{username, email, created_at, updated_at}`.
- Registration is intentionally minimal: **username + email + password**.
  Login is **email + password** (Firebase Auth signs in by email).

## Verify

```sh
flutter analyze
flutter test
```

After `google-services.json` is in place you can confirm the connection by
registering a new account: the Profile screen then shows **Cloud account**
instead of "Local mode".