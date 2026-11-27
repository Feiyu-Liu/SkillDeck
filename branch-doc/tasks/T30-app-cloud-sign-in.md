# ExecPlan: T30 App: Cloud sign-in in Settings

Milestone M7, part 2. It does not depend on M6 or T29, so it can run in
parallel with T29. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

On a macOS build with a service origin, a person signs in to SkillDeck Cloud
from Settings with Device Authorization, sees the signed-in account, and signs
out. A build without an origin, and every Windows build, shows no Cloud UI.

### Context

- **Read first:**
  - `../phase1-plan.md`: Sign-in (R14), Service origin (R16), and the App
    integration row of Components;
  - `../cloud-api-contract-v0.md`;
  - `packages/skills_cloud/lib/src/sign_in/`: `CloudSignIn`, `CloudDevice`,
    `CloudServiceOrigin`, `CloudSessionStore`, and their results;
  - `../windows-http-2026-11-23.md`, for why Windows stays off;
  - the App's Settings feature and how `self_update` reads its
    `String.fromEnvironment` values.
- **R14:** the App never collects a password or OTP, never opens a loopback
  listener, and never registers a URL scheme. The person approves in the
  browser.

### Contract

- **Origin:** a new define, `SKILLDECK_CLOUD_ORIGIN`. Empty, invalid, or
  running on any platform other than macOS means Cloud is off: no Cloud
  provider builds a client, and Settings shows nothing about Cloud. Add the
  key to the define files' documentation; do not commit a real staging or
  production origin to `debug.json` unless the maintainer says so.
- **HTTP client:** inject a `package:http` `Client` backed by `cupertino_http`
  on macOS. Pick the newest stable version that resolves with the locked
  Flutter 3.50.0, lock it, and record the version in the Decision Log.
- **Session storage:** `SecureCloudSessionStore` implements
  `CloudSessionStore` over `flutter_secure_storage` 11.0.0, keyed by origin.
  It stores only what `StoredCloudSession` holds. Nothing about the session is
  logged, put in analytics, or written to App settings.
- **Device description:** `CloudDevice` from the macOS computer name, trimmed
  to the contract's 64 code points, with platform `macos`.
- **Settings section "SkillDeck Cloud":**
  - **signed out:** a "Sign in" button. It starts sign-in, shows the user code
    and a button that opens the verification URL in the default browser, and
    waits. Cancel stops polling.
  - **result states:** denied, expired, and failed each show a message and a
    way to start again. `rate_limited` is retried as T19 defined.
  - **signed in:** the account's name and email, and "Sign out".
  - **session unavailable** (offline at launch): the account stays shown, with
    a quiet "offline" note.
  - All strings go in `app_en.arb` and `app_zh.arb`.
- **Riverpod:** a provider for Cloud availability, one for `CloudSignIn`, and
  a ViewModel for the section. ViewModels call the providers; views do no
  platform I/O.

### Acceptance

- **Unit and widget tests** with `InMemoryCloudSessionStore` and a
  `MockClient` service:
  - no origin, an invalid origin, and a non-macOS platform each hide the
    section and build no client;
  - full sign-in: code shown, browser launch requested with the verification
    URL, success shows the account;
  - cancel, denied, expired, failed, and offline-at-launch;
  - sign out deletes the session from the store.
- **Secure store:** a test with the plugin's test double; the stored value
  holds only the session fields.
- **No leaks:** a test searches log output, analytics events, and the App
  settings file after sign-in for the token and the email, and finds neither.
- **Manual check on macOS,** if the maintainer runs staging sign-in: record
  the steps and the result in Outcome; otherwise say it was not run.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code.

### Scope fence

- **In scope:** `skilldeck-app/lib/features/cloud/` (sign-in parts), Settings
  wiring, l10n, define documentation, the App's `pubspec.yaml` and lock.
- **Out of scope:**
  - the sync runtime and Sync Status (T31);
  - Windows and Linux Cloud;
  - GitHub sign-in setup on the service;
  - `skills_cloud` changes. If one is needed, stop and ask.

### Stop and ask if

- `cupertino_http` does not resolve with the locked toolchain.
- The macOS computer name is not readable without a new entitlement.
- Any step would need a loopback listener or a URL scheme.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
