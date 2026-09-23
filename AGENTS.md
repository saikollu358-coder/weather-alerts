# AGENTS.md

Agent working conventions for this repository.

## Validation commands

Run after every phase and before declaring work complete:

```sh
flutter analyze
flutter test
```

Full release gate (only at project completion):

```sh
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web
```

## Conventions

- Keep Clean Architecture: `core/`, `data/`, `domain/`, `features/`, `services/`.
- No business logic in widgets. UI talks to providers -> usecases -> repositories.
- No secrets, API keys, passwords, or Firebase configs in code. All configuration
  enters via `--dart-define` or platform config files (see `lib/core/config/app_config.dart`).
- Never modify safety thresholds to make tests pass. Centralize weather rules in
  `lib/services/weather_analysis/` and port to `functions/` verbatim.
- The app is a *weather risk assessment*, never a disaster prediction guarantee.
  Official warnings always take precedence.
- Every weather screen shows a "Last updated:" timestamp and a stale indicator.
- Keep deterministic, rule-based safety decisions. No LLM in the alert path.
- Update documentation (`documentation/`) when architecture changes.