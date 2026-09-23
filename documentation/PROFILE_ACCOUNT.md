# Profile & Account (Phase 16)

Makes the profile editable (display name) and links it to Settings.

## Scope

- **Editable display name** for cloud accounts, edited via an inline dialog on
  the Profile screen. Email stays read-only (changing it requires a Firebase
  re-authentication flow, out of scope).
- **Settings linkage**: a "Notifications & settings" row on the Profile screen
  navigates to `/settings`.
- Local/guest sessions have **no edit affordance** — there is no cloud account
  to persist to, and this is communicated on the screen.

## Flow

```
ProfileScreen (edit dialog)
  → AuthController.updateProfile(name)        [keeps session authenticated]
    → AuthRepositoryImpl.updateProfile
      → FirebaseAuthService.updateProfile      updateDisplayName → reload → remap
      → Firestore users/{uid}/profile/default  {username, updated_at} (merge)
```

- `firestore.rules` already grants the owner write access to
  `users/{uid}/profile/default`; no rule changes were needed.
- `AuthController.updateProfile` returns the user-safe error message on failure
  (null on success). Unlike login/register, a failed edit **does not** drop the
  user to the sign-in screen — the authenticated session is preserved.
- The UI refreshes immediately because the controller assigns
  `AuthState.authenticated(updatedUser)`; `authStateChanges` would otherwise
  not emit for a display-name change.

## Supporting changes

- `AuthService` / `AuthRepository` gained `updateProfile({required String name})`.
- `AuthRepositoryImpl` now depends on the narrow `CloudDataStore` interface
  (it only reads/writes documents), enabling repository tests.
- `FakeAuthRepository` in `test/helpers/fakes.dart` gained `updateProfile` +
  `updateProfileError`; a shared `InMemoryCloudDataStore` and `FakeAuthService`
  were extracted for repository/service-level tests.

## Verification

```sh
flutter analyze
flutter test test/unit/auth_controller_test.dart test/unit/auth_repository_impl_test.dart test/widget/profile_screen_test.dart
```