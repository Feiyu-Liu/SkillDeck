# SkillDeck Cloud API contract v0: conventions and sign-in

Status: draft, 2026-11-26. Milestone M3. Written in this repository at the
maintainer's request; the private service repository implements it. Source of
truth for the decisions: R14 and R16 of the accepted ADR-0105 revision
(`0105-revision-2026-11-23-proposal.md`).

This version covers only what sign-in needs: the conventions every request
follows, and the Device Authorization and session endpoints. The Library,
Head Pack, Head Advance, and Account Change Feed endpoints come in v0.1, with
M4, after the Revision Pack prototype reports (P2, P4). Nothing here may
assume their shape.

The auth endpoints are those of Better Auth's `deviceAuthorization` and
`bearer` plugins, at their default base path. They were checked against the
published `better-auth` 1.7.28 package source on 2026-11-26. Where this
contract adds to them, it says so.

## Conventions

- **Service origin:** one origin per environment, given to the client as
  configuration (R16). Production is `https://cloud.skilldeck.cc`, staging is
  `https://cloud-staging.skilldeck.cc`. Dev is a local `wrangler dev` origin.
  - An origin is a scheme, host, and optional port. It has no path, query,
    fragment, or userinfo.
  - The scheme is `https`. Plain `http` is allowed only for a loopback host
    (`localhost`, `127.0.0.1`, `::1`), for dev.
  - A build with no origin has Cloud off.
- **Paths:** auth endpoints are under `/api/auth/`. SkillDeck data endpoints
  will be under `/v0/` (v0.1).
- **Credentials:** the Cloud Session token travels only in the
  `Authorization: Bearer <token>` request header, and only to the origin that
  issued it. Device codes travel only in request bodies. Neither is ever put in
  a URL.
- **Bodies:** requests to the device endpoints are
  `application/x-www-form-urlencoded`, as RFC 8628 specifies. Responses are
  JSON. The client ignores response fields it does not know.
- **Caching:** the device endpoints answer with `Cache-Control: no-store`.
- **Too many requests** (added 2026-11-27, T19): any endpoint may answer
  HTTP 429 with `{"error": "rate_limited", "error_description": "<text>"}`.
  It means "try again later" and is not part of the RFC 8628 error table.
  - While polling `/device/token`, the client keeps polling at the current
    interval until the codes expire.
  - On any other call, the client reports a server failure; the caller may
    retry later.
  - The service may send `Retry-After`. The v0 client ignores it.
- **Errors:** the device endpoints answer an expected failure with HTTP 400
  and `{"error": "<code>", "error_description": "<text>"}`. The client acts
  only on `error`. It never shows or logs `error_description`.
- **Client identifier:** the App sends `client_id=skilldeck-desktop`. It is a
  public, fixed name, not a secret. The service accepts only this value
  (`validateClient`).

## Device Authorization

Codes expire after 10 minutes, and the poll interval is 5 seconds (maintainer,
2026-11-26). The client follows the `expires_in` and `interval` it receives,
so these values can change without a client change.

### 1. Request a device code

`POST /api/auth/device/code`

| Field | Required | Value |
|---|---|---|
| `client_id` | yes | `skilldeck-desktop` |
| `device_name` | yes | the name the person knows this Mac by: not empty after trimming, at most 64 Unicode code points. **Addition to Better Auth** |
| `device_platform` | yes | `macos` in Phase 1. **Addition to Better Auth** |

The service must show `device_name` and `device_platform` on the approval page
(R14, phishing mitigation). The standalone plugin drops unknown fields, so
the service needs its own code for them. That code is the service's choice.
It must not change the path or the other fields.

Success, HTTP 200:

| Field | Meaning |
|---|---|
| `device_code` | secret; used only to poll |
| `user_code` | shown to the person |
| `verification_uri` | the approval page, on the service origin |
| `verification_uri_complete` | the same page with the user code filled in; the App opens it in the system browser |
| `expires_in` | seconds until both codes expire |
| `interval` | minimum seconds between polls |

Failures: `invalid_request`, also for a missing or invalid `device_name` or
`device_platform`; `invalid_client`; HTTP 500 `server_error`.

The client rejects a response whose verification URIs are not on the service
origin, or not `https` (except a dev loopback origin).

### 2. Poll for the session

`POST /api/auth/device/token`

| Field | Value |
|---|---|
| `grant_type` | `urn:ietf:params:oauth:grant-type:device_code` |
| `device_code` | from step 1 |
| `client_id` | `skilldeck-desktop` |

Success, HTTP 200:

| Field | Meaning |
|---|---|
| `access_token` | the Cloud Session token. Opaque |
| `token_type` | `Bearer` |
| `expires_in` | seconds until the session expires |
| `scope` | empty in v0; ignored |

Failures, HTTP 400, and what the client does:

| `error` | Client action |
|---|---|
| `authorization_pending` | wait `interval`, poll again |
| `slow_down` | add 5 seconds to the interval for the rest of this sign-in (RFC 8628 §3.5), then poll again. Better Auth rejects polls that come early; it does not raise the interval itself |
| `expired_token` | stop: the codes expired |
| `access_denied` | stop: the person denied this Device |
| `invalid_grant`, `invalid_client`, `invalid_request` | stop: protocol failure |

The client also stops when `expires_in` from step 1 has passed. A connection
failure or an HTTP 5xx keeps polling at the current interval until then.

### 3. On the web (service only)

`GET /api/auth/device?user_code=…`, `POST /api/auth/device/approve`, and
`POST /api/auth/device/deny` serve the approval page. The App never calls
them. A person signs in there with email OTP (Resend) or GitHub.

## App sign-in: authorization code with PKCE

Added 2026-11-28, when the maintainer amended R14. This is how the App signs
in. Device Authorization above stays for clients without a browser window; the
App no longer uses it. Cards: T35 (service), T36 (client), T37 (App).

### Fixed values

- `client_id`: `skilldeck-desktop`, as for Device Authorization.
- `redirect_uri`: exactly `cc.skilldeck.signin:/callback`. A private-use
  scheme in reverse-DNS form (RFC 8252, section 7.1). The service accepts no
  other value.
- `code_challenge_method`: `S256` only.

### 1. Open the sign-in page (in the App's web authentication window)

```
GET /app/sign-in?client_id=skilldeck-desktop
  &redirect_uri=cc.skilldeck.signin:/callback
  &response_type=code
  &code_challenge=<BASE64URL(SHA-256(verifier)), 43 characters>
  &code_challenge_method=S256
  &state=<16–128 characters of [A-Za-z0-9_-]>
  &device_name=<as in Device Authorization>
  &device_platform=macos
```

- The App generates a new `code_verifier` (RFC 7636: 43–128 characters of
  `[A-Za-z0-9-._~]`, from a secure random source) and `state` for each
  attempt. Neither is stored outside memory, and neither is logged.
- The page is the same sign-in page as `/device`: email OTP, and GitHub when
  enabled. The same validation applies to `device_name` and `device_platform`.
- **Once the person is signed in, the page redirects at once.** There is no
  confirmation screen and no code to compare. PKCE and the fixed redirect make
  a link sent by someone else useless: the code goes back only to the App on
  this Mac that started the attempt, and only that App knows the verifier.
- **Redirects:**
  - success: `cc.skilldeck.signin:/callback?code=<code>&state=<state>`;
  - the person chooses "Cancel" on the page:
    `cc.skilldeck.signin:/callback?error=access_denied&state=<state>`;
  - an invalid `code_challenge`, `state`, or device field:
    `...?error=invalid_request&state=<state>`.
- **A wrong `client_id` or `redirect_uri`** shows an error page and never
  redirects (RFC 6749, section 4.1.2.1).
- **After issuing a code,** the service ends the browser (cookie) session it
  created for this page. Nothing stays signed in on the web.

### 2. Exchange the code

`POST /app/token`, `application/x-www-form-urlencoded`:

| Field | Value |
| --- | --- |
| `grant_type` | `authorization_code` |
| `code` | from the redirect |
| `code_verifier` | the attempt's verifier |
| `client_id` | `skilldeck-desktop` |
| `redirect_uri` | `cc.skilldeck.signin:/callback` |

- **200:** the same body as a successful Device Authorization token response:
  `{"access_token": "<token>", "token_type": "Bearer", "expires_in": <s>}`,
  with `Cache-Control: no-store`. The token is a Better Auth session token,
  carrying the device name and platform from step 1, exactly like a Device
  session. Everything after this, including the Session section below, is
  unchanged.
- **400** with an RFC 6749 error code:
  - `invalid_grant`: the code is unknown, expired, already used, or the
    verifier does not match its challenge;
  - `invalid_request`: a missing or malformed field;
  - `invalid_client`: a wrong `client_id`;
  - `unsupported_grant_type`.
- **429** `rate_limited`, as in Conventions.

### Code rules (service)

- A code is random, at least 128 bits, single use, and valid for 60 seconds.
- It is bound to the challenge, `client_id`, `redirect_uri`, account, and
  device description. The service stores only its hash.
- A second use of a code fails with `invalid_grant`, and also revokes the
  session issued from it (RFC 6749, section 4.1.2).

### Credentials in URLs: the one exception

The authorization code travels in the callback URL. This is the one exception
to "never in a URL" in Conventions. It is acceptable because the code:
- lives for 60 seconds and works once;
- is useless without the verifier;
- reaches only the App's web authentication session.

The App never logs the callback URL, the code, the state, or the verifier.

## Session

The token from step 2 (of either sign-in) is a Better Auth session token. The `bearer` plugin
turns the `Authorization` header into the session on every request.

- **Read:** `GET /api/auth/get-session`. HTTP 200 with
  `{"session": {...}, "user": {...}}` while the session is live, or HTTP 200
  with `null` once it has ended (expired, signed out, or revoked). The client
  reads only:
  - `user.id`, an opaque account identifier;
  - `user.email`, shown in Settings;
  - `session.expiresAt`, an ISO 8601 time.
- **Sign out:** `POST /api/auth/sign-out` with an empty JSON body. It ends
  this Device's session only. The client deletes its stored token whatever
  the response, and a failed request is not retried.
- **Token renewal:** none in v0. Better Auth may send a `set-auth-token`
  response header; the client ignores it and keeps the token from step 2.
- **Any request:** HTTP 401 on a request with a token, or `null` from
  `get-session`, means the session has ended. The client deletes the token and
  reports sign-in required.

## Open in v0

- Telling "Device revoked" apart from "sign-in required" (the account-level
  conditions in `packages/skills_cloud/CONTEXT.md`). Better Auth reports both
  as an ended session. v0 reports both as sign-in required. A later version may
  add a SkillDeck endpoint for it.
