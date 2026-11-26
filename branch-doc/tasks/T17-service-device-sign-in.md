# ExecPlan: T17 Service side of Device sign-in (contract v0)

Milestone M3. **Runs in the private service repository, not here.** The
maintainer copies this card and `../cloud-api-contract-v0.md` into that
repository. Codex keeps the maintained sections of that copy; this file keeps
only the planner's part. Decisions: R14 and R16 of the ADR-0105 revision,
which the maintainer supplies privately. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

On the dev environment (`wrangler dev` with local D1), the service implements
every endpoint of contract v0. The SkillDeck client from T16 can then sign a
Device in, read its session, and sign it out, using only what the contract
says.

### Context

- **Read first:** the contract, then R14 (Device sign-in) and R16 (service
  origins and environments). The contract is binding; this card does not
  restate its fields or error table.
- **The client already exists.** T16 implemented it in this repository's
  `packages/skills_cloud/`, tested against a fake that follows the contract.
  Any difference between the service and the contract breaks it.
- **Facts checked in the `better-auth` 1.7.28 package source** (2026-11-26):
  - `/device/code` reads only `client_id`, `scope`, and `user_id`. It drops
    every other field.
  - The plugin's `grant` extension point is for other token grants. A grant
    must refuse the plugin's own session redemption, so it does not fit
    `device_name` and `device_platform`.
  - On `slow_down` the plugin rejects a poll that comes before the interval.
    It does not raise the interval; the client adds 5 seconds itself.
  - `/device/token` returns the new session's token as `access_token`, with
    `token_type: "Bearer"`.
  - `get-session` answers `null` with HTTP 200 when there is no session.
  - The `bearer` plugin turns an `Authorization: Bearer` header into the
    session.
- **Workers notes,** from section 2.7 of `../cloud-build-vs-adopt-survey.md`:
  - set `advanced.ipAddress.ipAddressHeaders` to `["cf-connecting-ip"]`, or
    every request shares one rate-limit bucket;
  - do not use Workers KV as `secondaryStorage`;
  - use the built-in Kysely adapter with the D1 binding;
  - D1 has no interactive transactions;
  - an auth instance at module scope must not hold pooled connections.
- **Decided:**
  - email OTP is sent through Resend;
  - each environment has its own GitHub OAuth App, with the callback on that
    environment's origin;
  - there are three environments: dev, staging, and production. Production is
    `https://cloud.skilldeck.cc`, staging is
    `https://cloud-staging.skilldeck.cc`;
  - codes expire after 10 minutes, and the poll interval is 5 seconds
    (maintainer, 2026-11-26).

### Contract

What the service must do. Anything not listed is your call; record it in the
Decision Log.

- **Endpoints:** `/api/auth/device/code`, `/api/auth/device/token`,
  `/api/auth/get-session`, and `/api/auth/sign-out`, exactly as the contract
  specifies them. Change no path, field, or error code.
- **Plugin settings:**
  - `validateClient` accepts only `skilldeck-desktop`;
  - `expiresIn` is 10 minutes and `interval` is 5 seconds;
  - `verificationUri` is `/device` on the same origin.
- **Device description:** `/device/code` also takes `device_name` and
  `device_platform`.
  - `device_name` is required. After trimming it must not be empty, and it may
    hold at most 64 Unicode code points. Count code points, not UTF-16 units.
  - `device_platform` is required and must be `macos`.
  - Anything else gets HTTP 400 with `invalid_request`.
  - Store both with the device code. They live and expire with it.
  - How you capture them is your choice, for example a small Better Auth
    plugin with a hook and its own table. Do not fork or patch `better-auth`.
- **Approval page, `GET /device`:**
  - served by the same Worker on the same origin, rendered on the server; no
    separate front-end project;
  - a person who is not signed in signs in first, with email OTP or GitHub,
    and comes back to the page;
  - the page shows the user code, the device name, and the platform, with
    Approve and Deny. It tells the person to approve only a sign-in they have
    just started on their own Mac;
  - every value from the request is HTML-escaped.
- **Plugins:** pin `better-auth` to 1.7.28. Enable only `deviceAuthorization`,
  `bearer`, `emailOTP`, and the GitHub social provider.
- **Rate limits:** keyed by `cf-connecting-ip`, and kept in D1 or another
  consistent store. Not in Worker memory.
- **CORS:** off. The client is a desktop App.
- **Logs:** never log a session token, device code, user code, email address,
  device name, or OTP, also not inside an error or a URL.
- **Secrets:**
  - only in Wrangler secrets, or in a local `.dev.vars` that git ignores;
  - list each secret's name, never its value, in the repository's README.
- **Email in dev:** dev cannot send real email. Use a sender that writes the
  OTP to the local console. The staging and production configurations must
  not be able to enable it.

### Acceptance

Each item is a test that runs in the Workers runtime against a local D1, for
example with `@cloudflare/vitest-pool-workers`, unless noted.

- **Contract conformance:**
  - each endpoint's method, request content type, request and response
    fields, and `Cache-Control: no-store` match the contract;
  - every row of the contract's token error table occurs in a test:
    `authorization_pending`, `slow_down` for an early poll, `expired_token`,
    `access_denied`, `invalid_grant`, `invalid_client`, and
    `invalid_request`;
  - a device code yields a token only once;
  - a wrong `client_id` gets `invalid_client` from `/device/code`.
- **Device description:**
  - a missing, empty, too long, or wrong-platform value gets `invalid_request`;
  - a 64-code-point name with characters outside the BMP is accepted;
  - the approval page shows the name and the platform;
  - a name holding HTML is shown escaped.
- **Approval:**
  - the approval page asks a signed-out person to sign in first;
  - after Approve, the next poll returns a token, and `get-session` with that
    token returns the account;
  - after Deny, the next poll returns `access_denied`.
- **Sessions:**
  - after `sign-out`, the same token's `get-session` returns `null`;
  - signing out one Device leaves another Device of the same account signed in.
- **Logs:** a test captures the Worker's log output during a full sign-in and
  finds none of the values listed under Logs.
- **End to end (manual):** on dev, sign in through the whole flow with the
  contract's requests. Use curl or a small script; driving T16's client is
  welcome but not required. Record each step's result in Outcome.
- **Gates:** the repository's own lint, type check, and test commands, and the
  D1 migrations applied to an empty database. Report each command's own exit
  code.

### Scope fence

- **Out of scope:**
  - deploying to staging or production. The staging configuration exists and
    lists the secrets it needs; the maintainer deploys it;
  - the data endpoints: Library, Head Pack, Head Advance, and the Account
    Change Feed (contract v0.1, with M4);
  - telling "Device revoked" apart from "sign-in required";
  - a web page that lists or revokes Devices;
  - Teams and the `organization` plugin;
  - changing the contract. Propose a change instead; see Stop and ask.
- **Expected size:** about 15–30 files, 1,200–2,500 lines including tests.

### Stop and ask if

- A contract item cannot be met without changing a path or field, or without
  patching `better-auth`.
- `better-auth` 1.7.28 does not work on Workers or D1, and another version
  seems needed.
- The approval page seems to need a separate front end or another origin.
- A Cloudflare product beyond Workers and D1 seems needed, such as KV,
  Durable Objects, or Queues.

## Maintained by Codex

Kept in the service repository's copy of this card.
