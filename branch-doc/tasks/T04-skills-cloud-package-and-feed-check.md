# ExecPlan: T04 The `skills_cloud` package and Feed Check scheduling

Milestone M2. Independent of T01–T03. Plan: `../phase1-plan.md`.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

`packages/skills_cloud` exists as a pure Dart package with its own CI. Its
first content is the Feed Check scheduler: it decides when to run a Feed Check
and makes sure only one runs at a time.

### Context

- Decision: R8. Feed Checks run on launch, on returning to the foreground, on
  reconnecting, on waking from sleep, and every 2 minutes while the App runs,
  even in the background. The service can lengthen the interval with
  `Retry-After`. Failures back off with jitter, up to a cap.
- R17: the package is pure Dart and will later talk only to the
  `package:http` `Client` interface. This task adds no HTTP at all.
- Vocabulary: **Feed Check** and **Account Change Feed** in
  `packages/skills_cloud/CONTEXT.md`.
- Templates to copy:
  - `packages/skilldeck_cli/pubspec.yaml` and `analysis_options.yaml`, for
    the package setup;
  - `.github/workflows/skilldeck-cli-ci.yml`, for CI.

### Contract

Names are provisional.

- `FeedCheckScheduler`, constructed with:
  - a callback that runs one Feed Check and returns one of:
    - success;
    - success with a service-requested delay (from `Retry-After`);
    - failure.
  - an injected clock and timer source, and an injected random source for
    jitter.
- Trigger methods for launch, foreground, reconnect, and wake, plus `start` and
  `stop`.
- No public types for HTTP, the API, accounts, or sessions.

### Acceptance

All behaviour is tested with a fake clock, and no test sleeps in real time.

- **Periodic checks:** a check runs at start, then every 2 minutes.
- **Triggers:**
  - each trigger runs a check promptly;
  - triggers that arrive while a check is running cause one follow-up check,
    not one per trigger;
  - never more than one check runs at a time.
- **`Retry-After`:**
  - a service-requested delay lengthens the next periodic interval;
  - it never shortens the interval below 2 minutes;
  - foreground and launch triggers still run a check.
- **Failures:**
  - backoff grows with jitter up to a cap. Name the base and the cap as
    constants;
  - one success resets the backoff.
- **Stopping:** after `stop`, no further check starts, and a check in flight is
  allowed to finish.
- **Gates,** from `packages/skills_cloud/`:
  - `dart pub get --enforce-lockfile` (commit the lockfile)
  - `dart format --output=none --set-exit-if-changed .`
  - `dart analyze --fatal-infos`
  - `dart test`
- **CI:** the new workflow is path-filtered to `packages/skills_cloud/**` and
  runs those gates.

### Scope fence

- In scope: `packages/skills_cloud/` and one new workflow file.
- Out of scope:
  - HTTP, the API client, sign-in, and Reconciliation;
  - any App wiring, including detecting foreground, sleep, or network changes;
  - edits to `CONTEXT.md` files;
  - a README beyond a few lines.
- Expected size: about 6–8 files, roughly 300–500 lines including tests.

### Stop and ask if

- The scheduler seems to need knowledge of accounts, sessions, or Feed
  contents.
- A dependency beyond `test`, `lints`, and what the clock and timer injection
  strictly need seems necessary.

## Maintained by Codex

### Progress

- [x] Added the Dart package, scheduler, and path-filtered CI workflow.
- [x] Verified timing, trigger coalescing, backoff, and shutdown with a fake clock.

### Decision Log

- Periodic delays start when a check completes, so time spent checking never starts an overlapping check.
- Explicit lifecycle triggers run promptly. Periodic checks still observe the most recent applicable `Retry-After` deadline.
- Failures use equal jitter over an exponential window from a four-minute first ceiling to a 30-minute cap. The scheduler treats callback exceptions as failures.
- `fake_async` is a development dependency. The scheduler uses SDK timers and a monotonic clock in production.

### Surprises

- The repository workflow policy test enumerates workflows and now covers the Cloud path filter and commands.

### Follow-ups

- The App supplies the lifecycle events and the Feed Check callback at integration.

### Outcome

Dart 3.14.0 passed the enforced lockfile, formatting, strict analysis, and all 10 fake-clock tests. The workflow policy suite passed all four tests. Hosted CI execution is pending.
