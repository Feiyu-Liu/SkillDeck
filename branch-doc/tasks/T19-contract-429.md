# ExecPlan: T19 HTTP 429 in contract v0 and the sign-in client

Milestone M3 follow-up. Fixes item T17-2 of
`../reviews/2026-11-27-m3-review.md`. Implemented by Claude at the
maintainer's request. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

A rate limit never ends a sign-in. The contract says what HTTP 429 means, and
T16's client follows it.

### Context

- The service answers HTTP 429 `{"error": "rate_limited", ...}` when a Better
  Auth limit trips. Contract v0 did not list it.
- T16 mapped every status below 500 other than 200 to a protocol failure, so a
  rate-limited poll ended the sign-in.

### Contract

- **Contract v0, Conventions:** add "Too many requests". Any endpoint may
  answer 429 `rate_limited`, meaning "try again later". It is not part of the
  RFC 8628 table. The v0 client ignores `Retry-After`.
- **`CloudSignIn.complete`:** a 429 poll keeps polling at the current interval,
  as a 5xx does.
- **`start` and `currentSession`:** a 429 reports `CloudFailureCode.server`.
  `currentSession` keeps the token, as for any unavailable answer.
- No public API change.

### Acceptance

- A poll sequence of a connection failure, a 503, a 429, and a token ends in
  sign-in, after four polls.
- `start` answered with 429 reports `server`.
- `currentSession` answered with 429 reports unavailable with `server`, and
  the token stays stored.
- All existing `skills_cloud` tests pass.
- **Gates:** the T16 gates.

### Scope fence

- **In scope:** the contract and `packages/skills_cloud/`.
- **Out of scope:** honoring `Retry-After`; the service side (T18).
- **Expected size:** 3 code files, under 50 lines.

## Maintained by the implementer

### Progress

- [x] Added "Too many requests" to the contract's Conventions.
- [x] Mapped 429 to `server`, and kept polling on 429.
- [x] Extended the polling test and added the `start` and `currentSession`
  cases.
- [x] Ran the gates on the box.

### Decision Log

- One change in the status mapping covers `start`, `currentSession`, and the
  account read after a token. The polling branch handles 429 next to 5xx.
- A 429 on the account read right after the token ends the sign-in with a
  `server` failure, as a 5xx does there. It is not retried, so only a full
  success writes the store, as T16 decided.

### Surprises

None.

### Follow-ups

- T18 fixes the service side of the approval page limit.

### Outcome

Commit `6aadbbf`. Three files: `cloud_sign_in.dart` (+7 / −2) and two test
files. The polling test now waits 20 s for four polls instead of 15 s for
three.

Mutation check: with the 429 handling removed from both places, 3 tests fail;
with it restored, all pass.

Box, Linux x64, Dart 3.14.0, at `6aadbbf`, from `packages/skills_cloud/`:

| Command | Exit | Result |
|---|---:|---|
| `dart pub get --enforce-lockfile` | 0 | Lockfile unchanged |
| `dart format --output=none --set-exit-if-changed .` | 0 | Clean |
| `dart analyze --fatal-infos` | 0 | No issues |
| `dart test` | 0 | 57 passed |
