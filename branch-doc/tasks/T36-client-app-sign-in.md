# ExecPlan: T36 Client: App sign-in with an authorization code and PKCE

In `packages/skills_cloud`. It implements the client side of "App sign-in:
authorization code with PKCE" in `../cloud-api-contract-v0.md`. It can run in
parallel with T35, against a fake. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can sign in through a web authentication window that the App
provides, and ends with the same stored session and account as a Device
Authorization sign-in.

### Context

- **Read first:** the contract section; `lib/src/sign_in/cloud_sign_in.dart`,
  especially how it finishes a sign-in, stores the session, and reads the
  account; and its tests and fake service in `test/support/`.
- **Reuse** the existing finishing path after the token arrives: storing the
  session for the origin and reading the account. The new flow differs only
  in how it gets the token.

### Contract

- **Port:** `CloudWebAuthenticator`, one method:
  `Future<Uri?> authenticate(Uri url, {required String callbackScheme})`.
  It returns the callback URL, or null when the person cancelled. The App
  implements it in T37.
- **`CloudSignIn.signInWithBrowser(CloudDevice device, CloudWebAuthenticator
  authenticator)`** returns the existing `CloudSignInResult`:
  1. Make a verifier, its S256 challenge, and a state, from `Random.secure`.
  2. Build the sign-in URL on the origin, with the contract's parameters.
  3. Call the authenticator.
     - Null means `CloudSignInCancelled`.
     - Check the callback's scheme, path, and `state`. Any mismatch means
       `CloudSignInFailed(protocol)`, and the code is not exchanged.
     - `error=access_denied` means `CloudSignInDenied`; any other `error`
       means `CloudSignInFailed(protocol)`.
  4. Exchange the code. Map the results:
     - 200 means finish as today, giving `CloudSignInSucceeded`;
     - `invalid_grant` means `CloudSignInFailed(protocol)`;
     - 429 and 5xx mean `CloudSignInFailed(server)`;
     - a connection failure means `CloudSignInFailed(network)`.
- **One attempt at a time:** a second call while one is running throws a
  `StateError`.
- **No leaks:** no `toString`, exception message, or log contains the
  callback URL, code, state, verifier, or token.
- **Device Authorization stays in the package,** unchanged. Mark its start
  method's documentation "for clients without a web authentication window".

### Acceptance

Tests with the package's fake service, extended for `/app/sign-in` and
`/app/token`, and a fake authenticator:

- success ends with the stored session and account, like Device Authorization;
- the URL has every contract parameter, the challenge is the S256 of the
  verifier sent at exchange, and a new attempt gets a new verifier and state;
- cancelled, denied, other error, wrong state, wrong scheme, wrong path, and a
  missing code each give the right result, and no exchange is made for them;
- `invalid_grant`, 429, 500, and a connection failure each map as above;
- a second concurrent call throws;
- the no-leak test covers every new type and failure.
- **Gates:** T16's gates from `packages/skills_cloud/`, each with its own exit
  code, and line coverage of the changed files.

### Scope fence

- **In scope:** `packages/skills_cloud/` sign-in code, its fake, and its
  tests.
- **Out of scope:** the App (T37); the service (T35); removing Device
  Authorization.

### Stop and ask if

- Finishing the sign-in needs a change to `StoredCloudSession` or the session
  store.

## Maintained by Codex

### Progress

- [x] Implemented and verified PKCE generation, callback validation, error redaction, concurrency guard and shared session finishing.

### Decision Log

- Reuse the existing crypto dependency and existing session finishing. The native port may throw platform exceptions; the client drops their text and maps them to the existing protocol failure, shown as other by the App.

- The authenticator fake represents the browser page and callback; the HTTP fake serves /app/token. The package itself never fetches /app/sign-in, because that URL belongs to the App-provided system window.

### Surprises

### Follow-ups

### Outcome

Cloud package: 150 tests passed, strict analysis/format passed. cloud_sign_in.dart line coverage is 99.15%; full package 92.51%. Existing Device Authorization remains supported. See ../validation/t35-t39-2026-11-28.md.

Changes are committed separately by task; no push or deployment is included.
