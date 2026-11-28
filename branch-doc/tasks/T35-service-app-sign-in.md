# ExecPlan: T35 Service: App sign-in with an authorization code and PKCE

Runs in the private service repository. It implements the new section "App
sign-in: authorization code with PKCE" of `../cloud-api-contract-v0.md`,
added after the maintainer amended R14 on 2026-11-28. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

The service offers `GET /app/sign-in` and `POST /app/token` as the contract
describes. A person who signs in on that page returns to the App with a Cloud
Session, with no code to compare and no confirmation screen.

### Context

- **Read first:** the contract's "App sign-in" section in full, its
  Conventions, and the Session section; the service's Device Authorization
  code from T17 and T18: the `/device` page, the device token endpoint, and
  how a Device session gets its `deviceName` and `devicePlatform`.
- **Reuse:**
  - the `/device` page's sign-in forms (email OTP, and GitHub when enabled)
    and its styling. The new page differs only in what happens after
    sign-in;
  - the way the device token endpoint creates a bearer session. The new
    endpoint must produce the same kind of session, so get-session, sign-out,
    the data API, and revocation work unchanged.

### Contract

- **`GET /app/sign-in`:** validates the query parameters in this order:
  1. `client_id` and `redirect_uri` exact. Otherwise show the plain error
     page, with no redirect.
  2. `response_type=code`, `code_challenge` (43 characters of base64url),
     `code_challenge_method=S256`, `state`, and the device fields. Otherwise
     redirect with `error=invalid_request`.

  Then:
  - **Not signed in on the web:** show the sign-in forms. Keep the attempt's
    parameters across the email OTP steps and the GitHub round trip, in a
    short-lived server-side record keyed by a random value in an HttpOnly,
    Secure, SameSite=Lax cookie, not in a URL.
  - **Signed in:** issue a code and redirect at once. End the browser session
    first.
  - A "Cancel" link redirects with `error=access_denied`.
- **Codes:** a new D1 table in the identity database, with a migration. It
  holds the code hash, the challenge, the account, the device description, the
  expiry (60 seconds), a used flag, and the issued session ID. Expired rows are
  deleted by the existing scheduled sweep.
- **`POST /app/token`:** validates the form and exchanges a code, per the
  contract. A used code answers `invalid_grant` and revokes the session issued
  from it. Marking a code used and creating the session happen in one D1 batch,
  so two concurrent exchanges cannot both succeed.
- **Rate limits:** the same per-IP policy as the device token endpoint, and
  429 `rate_limited` as in Conventions.
- **Responses:** `Cache-Control: no-store` on both endpoints. Neither logs a
  code, verifier, state, token, or email.
- **Device Authorization stays,** unchanged.

### Acceptance

Tests in workerd, as T20 and T21 did:

- the full flow with email OTP returns a token, and get-session shows the
  device name and platform;
- the same with GitHub, using the existing test double;
- a signed-in browser session gets an immediate redirect, and no browser
  session remains afterwards;
- each validation case of step 1 and step 2 gives the right page or redirect;
- token errors: unknown code, expired code (with an injected clock), wrong
  verifier, wrong `redirect_uri`, wrong `client_id`, missing field;
- a code exchanged twice: the second gets `invalid_grant`, and the first
  session is revoked;
- two concurrent exchanges of one code: exactly one succeeds;
- Cancel redirects with `access_denied` and issues nothing;
- a search of captured logs finds no code, verifier, state, token, or email;
- the existing Device Authorization tests still pass;
- **staging:** deploy and run the flow once by hand in a browser, recording
  the steps, but only if the maintainer asks. Otherwise say it was not run.
- **Gates:** the service's typecheck, format, and full test suite, each with
  its own exit code.

### Scope fence

- **In scope:** the service's auth routes, the sign-in page, one migration,
  the scheduled sweep, and their tests.
- **Out of scope:**
  - the client and the App (T36, T37);
  - removing Device Authorization;
  - any change to the data API.

### Stop and ask if

- Creating the bearer session needs Better Auth internals that are not part of
  its public API.
- Better Auth already has a plugin that implements this flow exactly as the
  contract says. Then compare it with the contract before building your own.
- The GitHub round trip cannot keep the attempt without putting it in a URL.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
