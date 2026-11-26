# ExecPlan: T16 Device Authorization sign-in client

Milestone M3. Implements the client side of `../cloud-api-contract-v0.md`,
and fixes item 5 of `../reviews/2026-11-24-m1-m2-review.md`. Decisions: R14 and R16 of the ADR-0105 revision. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can sign a Device in through Device Authorization. It can then
report the signed-in account, and sign the Device out. It talks only to the
`package:http` `Client` it is given. It keeps the Cloud Session only in a
session store that the App will supply.

### Context

- Read `packages/skills_cloud/CONTEXT.md` (Identity and its Relationships) and
  the whole contract file. The contract fixes the paths, fields, error codes,
  and polling rules; this card does not repeat them.
- The service does not implement the contract yet. Every test uses a fake HTTP
  server or `MockClient` that follows the contract.
- `skills_cloud` has one component so far, `FeedCheckScheduler` (T04). Follow
  its style: pure Dart, injected timers and clocks, `fake_async` in tests.
- Out of this repository's reach: the approval page, email OTP, GitHub, and
  Better Auth's configuration. They are the service's work.
- The App side is M7: `cupertino_http`, `flutter_secure_storage` behind the
  session store, the Settings UI, and opening the browser. Do not start it.

### Contract

New public API of `skills_cloud`, exported from `lib/skills_cloud.dart`.
Names may change if the Decision Log says why. Expected failures are typed
results, not exceptions.

- **`CloudServiceOrigin`:** built from a string; rejects anything the
  contract's Conventions do not allow with `ArgumentError`.
- **`CloudDevice`:** the Device's name and platform, as sent in step 1. The
  name is trimmed, must not be empty, and is cut to 64 characters. The platform
  has one value, macOS.
- **`CloudSessionStore`:** an interface with read, write, and delete of the one
  stored session for an origin. The stored value holds the token and the
  origin it was issued by. Ship an in-memory implementation for tests and for
  the App's own tests.
- **`CloudSignIn`:** built with an `http.Client`, a `CloudServiceOrigin`, and a
  `CloudSessionStore`.
  - **Start:** given a `CloudDevice`, requests a device code. It returns either
    a pending sign-in, or a failure. The pending sign-in exposes the user
    code, both verification URIs, and the expiry time. It never exposes the
    device code.
  - **Complete:** given a pending sign-in, polls until it ends, and can be
    cancelled. Outcomes:
    - signed in, with the account;
    - denied;
    - expired;
    - cancelled;
    - failed.

    Only "signed in" writes the store.
  - **Current session:** reads the store and calls `get-session`. Outcomes:
    - signed in, with the account;
    - sign-in required, when there is no token, or `null`, or 401. The stored
      token is deleted;
    - unavailable, when the service cannot be reached or answers 5xx. The
      token is kept.
  - **Sign out:** calls `sign-out` when a token is stored, then deletes the
    token whatever the response.
- **Account:** the account identifier and email from `get-session`, plus the
  session's expiry.
- **Failures:** one small enum of codes is enough. It covers:
  - a protocol failure: an unexpected status, a malformed body, a URI off the
    origin, or a refused client;
  - a network failure;
  - a server failure.

  The enum carries no server text.
- **Feed Check (review item 5):** `FeedCheckResult.failure` takes an optional
  delay, as `success` already does. When it is given, it replaces the jittered
  backoff for the next check. Without it, behaviour is unchanged.

### Acceptance

Each item is a test with a fake server, and `fake_async` where time passes.

- **Request shape:** each request has the contract's method, path, content
  type, and fields. The token appears only in `Authorization`, and the device
  code only in the body. No URL holds either.
- **Polling:**
  - first poll after `interval`;
  - `authorization_pending` keeps the interval;
  - each `slow_down` adds 5 seconds;
  - polling stops at `expires_in` with expired, and sends no poll after it;
  - a connection failure and a 503 keep polling.
- **Stops:**
  - `access_denied` gives denied;
  - `expired_token` gives expired;
  - `invalid_grant` gives failed;
  - none of them writes the store.
- **Cancellation:** cancelling while waiting ends with cancelled at once,
  sends no further request, and writes nothing.
- **Success:** a 200 from the token endpoint, then `get-session`, gives signed
  in with the account, and the store holds the token for this origin.
- **Origins:**
  - `CloudServiceOrigin` accepts the production, staging, and loopback dev
    forms;
  - it rejects `http` on other hosts, a path, a query, a fragment, and
    userinfo;
  - a device-code response whose verification URI is on another origin, or
    not `https`, is a protocol failure;
  - a token stored for one origin is never sent to another.
- **Current session and sign out:**
  - all three current-session outcomes, with the token kept or deleted as
    stated;
  - sign out deletes the token after a 200, a 500, and a connection failure.
- **No leaks:** the `toString` of every public type and the failure values
  never contain the token, the device code, the user code, or the email. A
  test builds each with known values and checks.
- **Review item 5:** a failure with a delay schedules the next check after
  that delay, and the following failure without one returns to the backoff.
  The existing scheduler tests pass unchanged.
- **Gates,** from `packages/skills_cloud/`:
  - `dart pub get --enforce-lockfile`;
  - `dart format --output=none --set-exit-if-changed .`;
  - `dart analyze --fatal-infos`;
  - `dart test`.

  Report each command's own exit code. `skills_cloud` has no coverage gate
  yet; report its line coverage for the new files anyway.

### Scope fence

- **In scope:** `packages/skills_cloud/`, and its `CONTEXT.md` if a term is
  missing.
- **Dependency:** add `http` to `skills_cloud`, at the version that
  `skills_workspace` and the App already lock (1.6.0). No other new runtime
  dependency.
- **Out of scope:**
  - the App, `cupertino_http`, `flutter_secure_storage`, and opening the
    browser (M7);
  - Library, pack, Head Advance, and feed calls (contract v0.1, M4);
  - telling "Device revoked" apart from "sign-in required" (open in the
    contract);
  - token renewal and `set-auth-token`;
  - retry or backoff outside sign-in polling;
  - any change to `skills_workspace`, or to `FeedCheckScheduler` beyond item 5;
  - code from the earlier prototype branch, except as the plan allows. Say
    what you carried over in the Decision Log.
- **Expected size:** about 8–14 files, 700–1,200 lines including tests.

### Stop and ask if

- The contract is ambiguous or seems wrong on a point a test needs. Do not
  guess; name the point.
- A behaviour needs a second runtime dependency, `dart:io` in `lib/`, or a
  platform check.
- The contract seems to need a field or endpoint it does not list.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
