# SkillDeck Cloud: build-vs-adopt survey

Date: 2026-11-23. Scope: the client (`skills_cloud`, Flutter desktop on macOS and Windows) and the private Cloudflare service, evaluated against the proposed ADR-0105 revision (R1–R13) and the draft `skills_cloud` CONTEXT. Research only. Nothing in the repository was changed.

## How the evidence was gathered

This session's network allowed only a few hosts. `developers.cloudflare.com`, `better-auth.com`, `docs.powersync.com` and most vendor sites could not be fetched directly. Claims were therefore verified, in order of preference, against:

1. **Official documentation source repositories, read at a known commit:**
   - `cloudflare/cloudflare-docs` @ `1c6e632` (2026-11-22), covering Artifacts, Durable Objects, D1, the China Network, Containers, Vectorize and Workers AI;
   - `better-auth/better-auth` @ `7e229f0` (2026-11-22), covering docs and plugin source.
2. **Package registry APIs:** pub.dev `/api/packages` and `/score` for version, date, license, platforms and publisher; the npm registry for version, date and license.
3. **Git tags and license files** of upstream repositories, read through `git ls-remote` and shallow clones. The tag commit date is used as a proxy for the release date.
4. **Web search snippets of official pages.** These are marked *(search)*. Third-party or secondary sources are marked *(secondary)*. Anything that could not be confirmed is marked **UNVERIFIED**.

Dates are the latest stable release unless stated otherwise.

---

## 1. Executive summary

**Cloudflare Artifacts exists and broadly fits the Git design.** It went to private beta on 2026-04-16 and open beta on 2026-10-01, and it is billed on Workers Paid. It provides:

- one isolated repository per Lineage Generation or Channel;
- standard smart-HTTP clone, fetch and push;
- per-repository `read`/`write` tokens with a TTL from 60 s to 1 year, revocable, minted from a Worker binding;
- asynchronous push events;
- EU/US jurisdictions.

**Artifacts has gaps the design must absorb:**

- no protected refs, pre-receive hooks or custom authorization;
- no documented anonymous read and no documented custom Git domain;
- push over receive-pack v1 only;
- limits of 1 GB per repository, 64 MiB per push and 32 MiB per file;
- no presence on the Cloudflare China Network;
- undocumented object garbage collection.

**On identity, adopt Better Auth 1.7.x for nearly all of it.** It has native D1 support. Its plugins cover email OTP, bearer sessions, per-session listing and revocation, RFC 8628 device authorization (which returns a Better Auth session token), GitHub sign-in, and later organizations and roles. The Git Access Token needs no JWT work, because Artifacts mints repository-scoped tokens itself.

**On the client, keep the hand-rolled approach and adopt only thin platform pieces:**

- `cupertino_http`, for both HTTP and WebSocket on macOS;
- possibly `win_http`, a young WinHTTP client for Windows under GPL-3.0;
- `package:web_socket`;
- the existing `flutter_secure_storage`.

**Reject the desktop OAuth plugins.** `flutter_appauth` has no Windows support. `flutter_web_auth_2` requires macOS 14.4, while the App targets macOS 12.0.

**Reject every local-first sync engine.** PowerSync, Electric, Couchbase, Realm, Firestore, Ditto and the CRDT bindings each do at least one of the following:

- write the local database directly;
- rely on a client upload queue, which is the outbox pattern the ADR forbids;
- need a backend other than D1;
- are end-of-life, proprietary or immature in Dart.

**For distribution and the Marketplace:**

- copy signing and registry practices from npm/PyPI provenance, TUF and pub.dev;
- federate outward by publishing an Agent Skills discovery index (`/.well-known/agent-skills/index.json`, schema 0.2.0), which the Workspace already consumes, rather than integrating with skills.sh, whose API is tied to Vercel OIDC.

---

## 2. Findings by area

Verdict key: **Adopt** · **Adopt partially** · **Prior art only** · **Reject**.

### 2.1 Desktop sign-in (client)

| Candidate | Covers | License | macOS / Windows | Maintenance | Fit vs. design | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hand-rolled PKCE loopback (prototype `skills_cloud/lib/src/auth/loopback.dart`) | System browser, `127.0.0.1` ephemeral port, S256 PKCE, state | GPL-3.0-or-later (ours) | Both | Ours | Matches RFC 8252 and the "session only in secure storage" rule. It needs a small server endpoint that trades a one-time code and verifier for a Better Auth session (see 2.7). | **Adopt** (carry over) | branch `feat/cloud-personal-sync-20261115` |
| Better Auth device authorization (RFC 8628), used from Dart over plain HTTP | Device code, polling, `slow_down`. `/device/token` returns a **Better Auth session token**. | MIT | Both (plain HTTP) | better-auth 1.7.27, 2026-11-20 | Zero custom server code and no listener or URL scheme. Device-code phishing is a known risk, mitigated with `verification_uri_complete` and showing the device name. | **Adopt** as fallback sign-in | better-auth.com/docs/plugins/device-authorization |
| `oauth2` (dart-lang) | Authorization-code grant with PKCE, client credentials, password grant. No device grant and no loopback server. | BSD-3 | Both | 2.0.5, 2025-10-20; tools.dart.dev | Better Auth is not an OAuth authorization server in this design (sessions, not OAuth tokens). | **Prior art only** | pub.dev/packages/oauth2 |
| `openid_client` | OIDC relying party | BSD-3 | Both | 0.4.10+2, 2026-09-16; appsup.be | Needs an OIDC provider, which the design does not have. | **Reject** | pub.dev/packages/openid_client |
| `oidc` (Bdaya) | OIDC with desktop loopback | MIT | Both | 5.0.2, 2026-10-06 | Same as `openid_client`. Adds several platform plugins. | **Reject** | pub.dev/packages/oidc |
| `flutter_appauth` | AppAuth wrapper | BSD-3 | macOS only (no Windows) | 13.0.0, 2026-10-30 | Has no Windows support. | **Reject** | pub.dev/packages/flutter_appauth |
| `flutter_web_auth_2` | ASWebAuthenticationSession on macOS. Embedded WebView2, or a `http://localhost:{port}` callback, on Windows. | MIT | Both, but macOS 14.4+ required since v4 | 6.1.0, 2026-11-22 | The App's deployment target is macOS 12.0 (`skilldeck-app/macos/Podfile`). The default Windows path is an embedded webview. | **Reject** | github.com/ThexXTURBOXx/flutter_web_auth_2 README |
| `desktop_webview_auth` (Invertase) | Embedded-webview OAuth | Apache-2.0 | Both | 0.0.16, 2025-10-28 | RFC 8252 discourages embedded webviews. Low maintenance. | **Reject** | pub.dev/packages/desktop_webview_auth |
| `app_links` | Custom-scheme and universal deep links | Apache-2.0 | Both | 7.2.2, 2026-10-06 | Needed only if a custom-scheme redirect is chosen over loopback. On Windows the scheme must be registered by the installer. | **Adopt partially** (only for the custom-scheme option) | pub.dev/packages/app_links |
| Community Better Auth Dart clients (`flutter_better_auth`, `better_auth_flutter`, `better_auth_client`) | Better Auth REST wrappers | MIT | Both | 0.6.6 (2026-11-02), 0.1.2 (2026-09-04), 0.15.2 (2026-10-06). All single-maintainer. | `flutter_better_auth` persists the session through `cookie_jar` and `hive_ce`, which breaks "tokens only in platform secure storage". The others are thin wrappers around `dio`. Better Auth ships no official Dart client (its integrations list has none). | **Reject** | pub.dev pages; better-auth `docs/content/docs/integrations/` |
| `flutter_secure_storage` (already a dependency at 11.0.0) | Keychain and Windows Credential Manager | BSD-3 | Both | 11.2.0, 2026-09-16 | Already used. It is the only store for the Cloud Session. | **Adopt** (existing) | pub.dev/packages/flutter_secure_storage |

### 2.2 Realtime WebSocket client (client)

| Candidate | Covers | License | macOS / Windows | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `package:web_socket` (dart.dev) | A transport-neutral `WebSocket` interface, with `IOWebSocket` (dart:io) and the browser implementation | BSD-3 | Both | 1.0.1, 2025-05-06 | Lets one reconnect supervisor run over `CupertinoWebSocket` on macOS and `IOWebSocket.fromWebSocket(dart:io WebSocket)` on Windows. `IOWebSocket.connect` takes no headers, so authenticate through `fromWebSocket` or a ticket. | **Adopt** | github.com/dart-lang/http/tree/master/pkgs/web_socket |
| `CupertinoWebSocket` (in `cupertino_http`) | `NSURLSessionWebSocketTask` behind the `package:web_socket` interface | BSD-3 | macOS | cupertino_http 3.1.1, 2026-11-03 | Uses the native stack, with proxy and VPN support. 3.1.1 "mitigates a memory leak when WebSocket connections are created". | **Adopt** (macOS) | cupertino_http CHANGELOG |
| `web_socket_channel` | Stream-channel API, including `AdapterWebSocketChannel` over `package:web_socket` | BSD-3 | Both | 3.0.3, 2025-04-17 | Optional sugar over the interface above. | **Adopt partially** (optional) | pub.dev/packages/web_socket_channel |
| `web_socket_client` (felangel) | Reconnect with constant, linear or binary-exponential backoff, plus a connection-state stream | MIT | Both | 0.2.1, 2025-05-22; single maintainer | It is bound to `web_socket_channel`'s default dart:io connect. No pluggable socket or headers are documented, so it cannot sit on `CupertinoWebSocket`. | **Prior art only** (copy the backoff and state model) | pub.dev/packages/web_socket_client |
| `partysocket` (JS) | Reconnecting WebSocket (a reconnecting-websocket fork) | MIT | n/a | 1.3.0, 2026-06-23; Cloudflare | Shows the reconnect semantics PartyServer clients expect. | **Prior art only** | github.com/cloudflare/partykit |

Server facts that shape the client:

- The Durable Object runtime answers protocol ping frames with pongs automatically, without waking a hibernated object. Client keep-alive pings are therefore free.
- Cloudflare's 2026-11-19 changelog says "some disconnects during runtime updates are still expected, so clients should continue to reconnect".

Build a small supervisor:

- full-jitter exponential backoff;
- a connect deadline;
- a reconnect that triggers Reconciliation (R8).

### 2.3 Native-stack HTTP clients (client)

| Candidate | Covers | License | macOS / Windows | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cupertino_http` (dart.dev) | `package:http` `Client` over NSURLSession, plus WebSocket. Uses Native Assets since 3.x. | BSD-3 | macOS (and iOS). The pub.dev platform tags overstate support; the README says macOS/iOS. | 3.1.1, 2026-11-03. 3.2.0-wip adds `onChallenge` for pinning and private CAs. | Avoids dart:io sockets on macOS. The Native Assets model matches `skills_workspace`. | **Adopt** (macOS) | pub.dev/packages/cupertino_http |
| `win_http` | `package:http` `Client` over async WinHTTP. Schannel TLS, system proxy (WPAD/PAC), HTTP/2, abort through `WinHttpCloseHandle`. Runs `http_client_conformance_tests`. | **GPL-3.0** (LICENSE is GPLv3 text; "only" vs "or later" not stated, **UNVERIFIED**) | Windows 8.1+ | 0.2.3, 2026-10-07; first published 2026-04-07; single maintainer (edde746); about 1.8k lines | It is the only maintained WinHTTP client found. GPL-3.0 can be combined with this GPL-3.0-or-later App, but the combined work is then distributed under GPLv3. It has no WebSocket support. Qualify it with the prototype's `tool/qualify_tls_cleanup.dart` stalled-TLS probe. | **Adopt partially** (qualify, then depend on it or vendor it) | github.com/edde746/win_http |
| `native_dio_adapter` | dio adapter over `cupertino_http` and `cronet_http` | Apache-2.0 | macOS native. Windows falls back to dart:io (no Windows implementation among its dependencies). | 1.8.0, 2026-07-29 | Adds dio and fixes nothing on Windows. | **Reject** | pub.dev/packages/native_dio_adapter |
| `package:http` `Client` interface | Abstraction | BSD-3 | Both | 1.6.0, 2025-11-10 | Lets `skills_cloud` stay pure Dart while the App injects `CupertinoClient`, a WinHTTP client, or `IOClient` on Linux. | **Adopt** | pub.dev/packages/http |
| `cronet_http`, `ok_http` | Android stacks | BSD-3 | Not applicable | n/a | Not applicable. | **Reject** | pub.dev |

### 2.4 Local-first and sync engines, and CRDTs (client)

The invariant being tested is that only a local Workspace transaction may change local Skill state, so no engine may write Workspace state or keep an intent outbox.

| Candidate | Covers | License | macOS / Windows | Maintenance | Fit vs. design | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PowerSync (`powersync` client and PowerSync Service) | Syncs Postgres, MongoDB, MySQL, SQL Server or Convex into a client SQLite database. Writes go through a client CRUD queue and `uploadData()`. | Apache-2.0 for both client and service (the service was checked at v1.29.1) | Both | Client 2.6.2 (2026-11-16); service 1.29.1 (2026-11-18); company-backed | The engine owns its own SQLite database. Its upload queue (`getCrudBatch`/`uploadData`, retried every 5 s) is exactly the client outbox the ADR forbids. There is no D1 source module, so it needs a separate Node service and a database. Compare-and-set and Note Conflict logic would still live in our backend. | **Reject** | github.com/powersync-ja/powersync.dart (`connector.dart`); powersync-service `modules/` |
| ElectricSQL | Postgres read-path sync | Apache-2.0 (server) | The Dart client is discontinued | Server active (2026-10); `electricsql` Dart client discontinued, last 0.8.2 on 2024-07-24 | Needs Postgres and has no maintained Dart client. | **Reject** | pub.dev/packages/electricsql |
| Couchbase Lite (`cbl` / cbl-dart) with Sync Gateway | Document database with replication | The wrapper is Apache-2.0. Couchbase Lite and Sync Gateway source is **BSL 1.1**, and the Community Edition binaries carry use restrictions. | Both | cbl 4.0.0, 2026-11-06 | Needs Sync Gateway plus Couchbase Server or Capella, and writes its own store. The licensing is a problem for the service. | **Reject** | couchbase/sync_gateway LICENSE; couchbase.com blog "Couchbase Mobile changes source code license to BSL 1.1" *(search)* |
| Realm / Atlas Device Sync | Object database with sync | Apache-2.0 (SDK) | Both | realm 20.2.0, 2025-09-24. **Device Sync reached end of life on 2025-09-30.** | End of life. | **Reject** | mongodb.com/docs/atlas/device-sdks/deprecation *(search)* |
| Firestore (FlutterFire) | Document database with an offline cache | BSD-3 (plugin) | macOS. Windows uses the Firebase C++ SDK, which Google labels **beta**. No Linux. | cloud_firestore 7.2.0, 2026-11-16 | A second backend that writes its own cache. Field-level last-writer-wins only. Google services are reported blocked in mainland China *(secondary)*. | **Reject** | firebase.google.com/docs/cpp/learn-more *(search)* |
| Supabase Realtime (`realtime_client`) | Phoenix-channel broadcast and Postgres changes | MIT | Both | 2.13.2, 2026-10-12 | A second backend that duplicates the Durable Object ping. | **Reject** | pub.dev/packages/realtime_client |
| Ditto (`ditto_live`) | Peer-to-peer and cloud sync | Proprietary (pub.dev shows "unknown"; Ditto license terms are order-form based) | Both | 5.2.0, 2026-10-27 | Proprietary, quote-based, and it owns its own store. | **Reject** | ditto.com/legal/supplemental/license *(search)* |
| Automerge, Yjs and Loro Dart bindings (`automerge` 0.0.0, `loro` 0.0.0, `loro_crdt` 0.1.0, `y_crdt` 0.2.0, `yjs_dart` 1.1.15) | CRDTs | MIT / BSD | Mixed | Mostly placeholders or single releases (2026), each from one maintainer | The ADR already rejects CRDTs for content. For metadata, "keep both Note texts" is not CRDT merge semantics, and server compare-and-set is simpler. | **Reject** | pub.dev |
| `crdt`, `sqlite_crdt` (cachapa) | Hybrid-logical-clock last-writer-wins tables | Apache-2.0 | `sqlite_crdt` lists web only | crdt 5.1.3 (2024-11-02) | Clock-based last-writer-wins contradicts server-ordered Field Versions. | **Prior art only** | pub.dev/packages/crdt |

**Conclusion:** none of these can carry the metadata channel without breaking either "only Workspace transactions change local state" or "no client queue". The metadata channel is about four field kinds with compare-and-set plus a change feed. Building it is smaller than integrating any engine.

### 2.5 Git in Dart (sanity check)

| Candidate | Covers | License | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| Existing vendored, pinned libgit2 with FFI and HTTPS transport | Revision engine, fetch and push, the recorded patches (strict redirects, disabled `FETCH_HEAD`, Windows path bounds) | GPL-2.0 with linking exception (libgit2) | Ours | Already meets ADR-0106. Artifacts accepts both a Bearer header (`http.extraHeader` form) and Basic auth with the token secret (the part before `?expires=`) as the password, so either the per-operation header or the userpass callback works. | **Keep** | — |
| `git2dart` (DartGit-dev) | libgit2 bindings | MIT | 0.5.6, 2026-09-04 | Would replace nothing and lose the recorded patches and the Native Assets build. | **Reject** | pub.dev/packages/git2dart |
| `libgit2dart` | libgit2 bindings | MIT | Discontinued (1.2.2, 2023) | Discontinued. | **Reject** | pub.dev/packages/libgit2dart |
| `dart_git` (GitJournal) | Pure-Dart Git | Apache-2.0 | 0.0.2, 2021 | Stale. | **Reject** | pub.dev/packages/dart_git |
| `git` (kevmoo) | Wraps the system `git` CLI | BSD-2 | 2.5.0, 2026-11-03 | Internal history must never use system Git. | **Reject** | pub.dev/packages/git |

### 2.6 Git hosting (server)

#### Cloudflare Artifacts: verified facts

All facts below come from cloudflare-docs @ 2026-11-22.

- **Status:**
  - private beta on 2026-04-16;
  - **open beta on 2026-10-01**;
  - Workers Paid plan only.
- **Billing start dates conflict:**
  - the open-beta changelog says "billing … on October 14, 2026";
  - the pricing page says operations and storage are billed from **November 19, 2026**;
  - both are past, but the exact start date is **UNVERIFIED**.
- **Interfaces:**
  - a Workers binding with `create`, `get`, `list`, `import`, `delete`, and on each repository `info`, `createToken(scope, ttl)`, `listTokens`, `revokeToken`, `fork`, `log`, `readCommit`, `readTree`, `readBlob` and `readFile`;
  - a REST API;
  - Wrangler commands and a dashboard;
  - local development through `wrangler dev`, with a local simulator since 2026-11-16.
- **Git:**
  - smart HTTP;
  - fetch over protocol v1 or v2, with shallow and deepen;
  - **push over receive-pack v1 only**;
  - the optional v1 capabilities `filter` and `include-tag` are unsupported;
  - no SSH endpoint and no LFS (these are stated for the local simulator).
  - The remote has the form `https://<ACCOUNT_ID>.artifacts.cloudflare.net/git/<namespace>/<repo>.git`. The April changelog showed a different form, so always use the server-returned `remote` and never persist it.
- **Isolation and authentication:**
  - each repository has its own history, refs, tokens and lifecycle;
  - tokens are repository-scoped, with scope `read` (clone, fetch, pull) or `write` (adds push);
  - TTL ranges from 60 s to 31,536,000 s, with a default of 86,400 s;
  - tokens can be revoked;
  - "Your Worker or API layer decides when to mint those tokens", so authorization stays outside the repository;
  - `create`, `import` and `fork` also return an initial token.
- **Events:** asynchronous Queue events:
  - `repo.created`, `repo.deleted`, `repo.forked` and `repo.imported`;
  - `pushed`, which carries ref, before, after and commits with parents;
  - `cloned` and `fetched`.
- **Not documented anywhere** (treat as absent):
  - protected refs, branch rules, pre-receive hooks or an authorization callback;
  - anonymous or public read;
  - a custom domain for the Git remote;
  - object garbage-collection behavior.
- **Limits:**
  - 1 GB per repository (for repositories created on or after 2026-09-29);
  - 1 TB per account, raisable;
  - unlimited repositories;
  - 64 MiB and 50,000 objects per push;
  - 32 MiB per file;
  - 1 MiB of ref updates per push;
  - 2,000 Git requests per 10 s per repository.
- **Pricing:**
  - 10,000 operations per month included, then $0.15 per 1,000;
  - content reads count 100:1 and token operations 5:1;
  - 1 GB-month included, then $0.50 per GB-month;
  - repository charges are "coming soon": 100,000 included, then $0.01 per repository.
- **Data location:** `eu` or `us` jurisdiction, chosen per namespace at creation and **immutable**.
- **Durability:** synchronous multi-datacenter replication plus asynchronous snapshots.

#### Git hosting options

| Candidate | Covers | License | Maintenance | Fit vs. design | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| **Cloudflare Artifacts** | Per-repository Git hosting, scoped tokens, binding reads | Proprietary managed service | Open beta since 2026-10-01; changelog active through 2026-11-16 | **Fits Phase 1:** one repository per Lineage Generation, write tokens minted only for the owning Device, the database Head as authority, and `readCommit` to check pushed objects before Head Advance. **Gaps for Phase 2+:** `refs/releases/*` cannot be protected by the host, so protection must come from token custody (clients never hold a Channel write token) and the database-authoritative Release commit IDs. With no public read, Marketplace federation needs an archive export. With no server ref API besides Git, deleting retention refs needs a Git push (for example isomorphic-git in a Worker) or a client-side cleanup push. | **Adopt** (Phase 1), with the qualification tests in section 4 | developers.cloudflare.com/artifacts/ (api/git-protocol, api/workers-binding, platform/limits, platform/pricing) |
| isomorphic-git inside a Worker | A Git *client*, usable in Workers with an in-memory filesystem. Cloudflare documents it for pushing to Artifacts. | MIT | 1.44.18, 2026-11-21 | Useful for server-side Channel writes (fetch the staged Release, verify the tree, push to the Channel repository with a server-held token) and for deleting retention refs. It is not a server: building our own smart-HTTP server on R2 would mean reimplementing pack negotiation. | **Adopt partially** (Phase 2 helper); a self-built Git server on R2 is **Reject** | developers.cloudflare.com/artifacts/examples/isomorphic-git/ |
| Cloudflare Containers running git-http-backend, Soft Serve, Gitea or Forgejo | Self-hosted Git with real hooks, so protected refs are possible | Soft Serve MIT (v0.12.4, 2026-10-23); Gitea MIT (v28.4.0, 2026-11-15); Forgejo **GPL-3.0-or-later** since v9 | Containers GA since 2026-04-13 | Full control, including pre-receive hooks. We would own durable storage, scaling, backups and upgrades. | **Reject** for now; keep as the exit plan | changelog/post/2026-04-13-containers-sandbox-ga; forgejo.org/2024-08-gpl *(search)* |
| GitHub through a GitHub App (org-owned private repositories) | Installation tokens that expire in 1 h and can be restricted to listed repositories and permissions (`contents: read`/`write`), plus rulesets for protected refs | Proprietary | Stable | The token model matches Git Access Tokens, and protected refs exist. GitHub's acceptable-use terms for "storage backend" usage, repository-creation rate limits, and mainland-China reachability are **UNVERIFIED**. | **Prior art only** (fallback) | docs.github.com …/generating-an-installation-access-token-for-a-github-app *(search)* |
| Hosted Git-storage APIs (Freestyle Git, Pierre Code Storage) | Programmatic repositories for agents | Proprietary | **UNVERIFIED** | Found only through search. Same class as Artifacts, outside Cloudflare. | **Prior art only** | freestyle.sh/products/git; code.storage *(search)* |

### 2.7 Better Auth on Workers and D1 (server)

The version is `better-auth` 1.7.27 (npm, 2026-11-20). It is MIT-licensed and company-backed: the docs also describe a paid "Better Auth Infrastructure" `dash()` plugin. Facts below come from the repository docs @ 2026-11-22.

**Workers caveats** (`docs/guides/cloudflare.mdx`):

- `nodejs_compat` is needed for compatibility dates before 2026-08-04.
- Set `advanced.ipAddress.ipAddressHeaders: ["cf-connecting-ip"]`. Otherwise all rate limiting falls into one shared bucket.
- Do not use Workers KV as `secondaryStorage`; it is eventually consistent and has no atomic operations.
- An auth instance at module scope must not hold pooled database connections.

**D1:**

- D1 works natively with `database: env.DB` through the built-in Kysely adapter.
- `getMigrations()` supports programmatic migrations, because the CLI cannot reach D1.
- **D1 has no interactive transactions.** Password-reset atomicity is therefore not guaranteed, and SCIM is unsupported on D1. Neither matters for Phase 1.

| Plugin / feature | Maps to | Fit | Verdict | Source |
| --- | --- | --- | --- | --- |
| Core with native D1 (Kysely) | Accounts, sessions | DB-backed sessions, as decided | **Adopt** | docs/concepts/database |
| `emailOTP` | Email OTP sign-in | Defaults: 6 digits, 300 s, 3 attempts. The App can call it in-app, with no browser needed. | **Adopt** | docs/plugins/email-otp |
| GitHub social provider | GitHub sign-in | Needs a browser and a handoff (see below) | **Adopt** | docs/authentication/github |
| `bearer` | Cloud Session in the `Authorization` header | Returns the session token in the `set-auth-token` response header. The App stores it in secure storage. | **Adopt** | docs/plugins/bearer |
| Session management (`listSessions`, `revokeSession`, `revokeOtherSessions`) | Per-Device revocation | Model a Device as one session plus additional fields or our own `devices` table | **Adopt** | docs/concepts/session-management |
| `deviceAuthorization` (RFC 8628) | Fallback desktop sign-in | `/device/token` returns a Better Auth session token. It can also be composed with the OAuth Provider plugin, which is not needed here. | **Adopt** (fallback) | docs/plugins/device-authorization |
| `@better-auth/electron` (server plugin with PKCE one-time token exchange) | Desktop handoff pattern | A system-browser sign-in produces a one-time token stored with the PKCE challenge and state. `/electron/token` exchanges it with the `code_verifier` for a fresh session (about 340 lines in `routes.ts`). Whether its browser helper allows a loopback redirect rather than a custom scheme is **UNVERIFIED**. | **Prior art only**: copy the pattern into a small `/desktop/token` plugin, or reuse it if loopback works | docs/integrations/electron; `packages/electron/src/routes.ts` |
| `jwt` / JWKS | Short-lived signed tokens | **Not needed for Git**, because Artifacts mints repository tokens. Optional for a short-lived WebSocket ticket verified in the Durable Object without a database read. | **Adopt partially** (optional) | docs/plugins/jwt |
| `organization` | Team, Membership, invitations | Default roles are owner, admin and member. Custom roles come from `createAccessControl` and dynamic roles, so Publisher can be a custom role. Invitations and sub-teams are included. The last-Owner rule and Team audit history are ours to build; Better Auth's audit logs belong to the paid `dash()` product. | **Adopt partially** (Phase 3) | docs/plugins/organization; docs/infrastructure/plugins/audit-logs |
| `api-key` | Machine keys | Not part of the Cloud Session design | **Reject** (for now) | docs/plugins/api-key |
| `multi-session` | Several accounts in one browser | Not needed | **Reject** | docs/plugins/multi-session |
| `oauth-provider` | Better Auth as an OAuth 2.1 / OIDC authorization server | Would replace DB bearer sessions with OAuth tokens, contradicting the decision. Possibly useful later for third-party integrations. | **Reject** (Phase 1) | docs/plugins/oauth-provider |
| `better-auth-cloudflare` (zpg6) | Community Workers/D1/KV/R2 glue | Superseded by native D1 support. Single maintainer. | **Reject** | npm 0.4.1, 2026-10-12 |

### 2.8 Realtime on Durable Objects (server)

| Candidate | Covers | License | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| Plain hibernatable WebSockets (`state.acceptWebSocket`) | One Durable Object per account broadcasting payload-free pings after the D1 commit | Platform | GA. Reliability improvement on 2026-11-19. | The runtime auto-answers pings without waking the object. Use `serializeAttachment` for per-socket Device IDs. Received-message limit 32 MiB. Pings need about 20 lines. | **Adopt** | developers.cloudflare.com/durable-objects/best-practices/websockets/ |
| PartyServer | A Durable Object base class unifying hibernated and non-hibernated objects, with `broadcast` and connection helpers | ISC | 0.5.10, 2026-08-03; Cloudflare | A convenience only, and pre-1.0. The client protocol stays plain WebSocket, so Dart compatibility is fine. | **Adopt partially** (optional) | github.com/cloudflare/partykit `packages/partyserver` |
| Cloudflare Agents SDK (`agents`) | Durable-Object "agents" with state sync, `@callable` RPC, WebSockets and MCP | MIT | 0.34.0, 2026-11-20 | Built for AI agents, pre-1.0, and a large surface for a ping channel. | **Reject** | github.com/cloudflare/agents |

### 2.9 Release signing and supply-chain integrity (Phases 2–4)

| Candidate | Covers | License | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| Ed25519 publisher keys over the canonical Release Manifest (minisign/signify style) | Detached signatures. Verify on the client with `cryptography` (Apache-2.0, 2.9.0), `ed25519_edwards` (Apache-2.0, 0.3.2) or `webcrypto` (google.dev, 0.6.2). | Various permissive | Stable formats | `skills_workspace` already depends on `canonical_json`. Simple, offline-verifiable and Dart-native. Key custody and rotation is the real work. | **Adopt** (Phase 4, required for the Public Grant) | jedisct1/minisign (ISC, 0.12, 2025-01-15); pub.dev |
| Sigstore (cosign, Rekor, Fulcio; sigstore-js) | Keyless OIDC-bound signing with a transparency log | Apache-2.0 | cosign 3.1.4 (2026-10-20); rekor 1.6.5 (2026-11-22); sigstore-js 5.0.1 (2026-11-05) | Desktop signing needs an OIDC round-trip to Fulcio. The Dart client (`sigstore` 0.2.4) is unlisted, single-maintainer, with an unknown license. There is no Dart TUF client for the trust root. | **Prior art only** (revisit later; possibly verify on the server only) | github.com/sigstore/cosign; pub.dev/packages/sigstore |
| The Update Framework (TUF) | Rollback, freeze and mix-and-match protection for catalog metadata | Apache-2.0 / MIT | python-tuf 7.0.1 (2026-09-01); go-tuf 2.4.2 (2026-05-19); tuf-js 6.0.3 (2026-11-19). **No Dart TUF client on pub.dev.** | Copy the concepts: a service-signed, versioned, expiring snapshot and timestamp over the public index. | **Prior art only** (adopt a subset in Phase 4) | github.com/theupdateframework |
| in-toto | Attestation format (PyPI accepts in-toto SLSA Provenance and PyPI Publish predicates) | Apache-2.0 | 3.1.0, 2026-04-25 | Useful vocabulary if build provenance is ever attested. | **Prior art only** | github.com/in-toto/in-toto; docs.pypi.org/attestations *(search)* |
| SSH-signed Git commits | Signing Release commits | n/a | n/a | Developers already have SSH keys. Through libgit2 this needs a signing callback, and verification needs an allowed-signers registry. | **Prior art only** | — |
| npm, PyPI and crates.io trusted publishing and provenance | OIDC-from-CI publishing without long-lived tokens; provenance on by default | n/a | npm trusted publishing GA 2025-07-31 (multiple configurations 2026-09-03); PyPI PEP 740 attestations (2024-11); crates.io trusted publishing (2025-07; GitLab 2026-01) | Model for "Releases from CI" later. Publish-by-OIDC maps to a Channel Grant for a CI identity. | **Prior art only** | docs.npmjs.com/trusted-publishers; docs.pypi.org/attestations; blog.rust-lang.org (2025-07-11) *(search)* |
| Homebrew bottle attestations | Sigstore-backed build provenance (beta, opt-in `HOMEBREW_VERIFY_ATTESTATIONS`) | BSD-2 | 2024 onward | Example of rolling verification out gradually, opt-in first. | **Prior art only** | docs.brew.sh/Homebrew-Security-and-Supply-Chain *(search)* |

### 2.10 Registry and marketplace prior art, and Agent Skills ecosystems

| Candidate | Covers | License | Maintenance | Fit / integration | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| **Agent Skills specification** | The SKILL.md format | Apache-2.0 (specification); CC-BY-4.0 (documentation) | Governance adopted 2026-11-04 as an LF Projects series; last commit 2026-11-04 | It is the content format SkillDeck manages. It defines no registry ("an API, a remote registry, or bundled assets" are left to clients). | **Adopt** (already the format) | github.com/agentskills/agentskills; agentskills.io |
| **Agent Skills discovery RFC v0.2.0** (Cloudflare) | `/.well-known/agent-skills/index.json` with `$schema` and `skills[]` entries {`name`, `type` (`skill-md` or `archive`), `description`, `url`, `digest` = `sha256:`} | Apache-2.0 | **Draft**, last commit 2026-03-24 | The Workspace already consumes it (`well_known_index.dart` pins schema 0.2.0). Federation path: publish each public Channel's latest Release as an `archive` entry with a digest from a Worker, so other clients can install SkillDeck Marketplace skills without SkillDeck. A digest gives integrity, not publisher authenticity. | **Adopt** (Phase 4 export) | github.com/cloudflare/agent-skills-discovery-rfc |
| **Claude Code plugin marketplaces** | `.claude-plugin/marketplace.json` with `name`, `owner` and `plugins[]` {`name`, `source`}. Sources can be a relative path, `github`, `git-subdir`, `url`, `archive`, `npm` or `command`, pinned by `ref`/`sha`. Official names are reserved. There is a separate Anthropic directory for submissions. | n/a | Current docs | The Workspace already parses `marketplace.json`. A public-Listings export as a marketplace is possible, but needs anonymously readable sources such as archives, because Artifacts has no public read. | **Adopt partially** (import exists; optional export in Phase 4) | code.claude.com/docs/en/plugin-marketplaces |
| `anthropics/skills` | Example marketplace.json and a spec copy | Per-skill licenses | Last commit 2026-11-16 | A test fixture source. | **Prior art only** | github.com/anthropics/skills |
| **skills.sh** (Vercel) and the `skills` CLI | A directory ranked by install telemetry, with partner security audits. The API is under `/api/v1/`, rate-limited to 600/min. | CLI MIT (v1.9.0, 2026-11-16); the directory is proprietary | Active | **API authentication requires a Vercel project OIDC token**, so in practice the caller must be deployed on Vercel. Its entries are mostly GitHub repositories, which SkillDeck can already install as Git Sources. | **Prior art only** (no federation dependency) | skills.sh/docs/api *(search)*; github.com/vercel-labs/skills |
| Open VSX (Eclipse) | Extension registry with namespace ownership claims, a publisher agreement, and pre-publish scanning with quarantine (rolled out in 2026) | EPL-2.0 | v1.4.0, 2026-11-09 | Moderation and namespace-verification model to copy. Its fail-open scanner bug is a lesson: fail closed. | **Prior art only** | github.com/eclipse/openvsx; blogs.eclipse.org (2026) *(search)* |
| pub.dev (`dart-lang/pub-dev`) | Verified publishers (DNS checked once at creation), retraction, discontinued flags | BSD-3 | Deployed 2026-11-19 | A model for publisher identity. | **Prior art only** | dart.dev/tools/pub/verified-publishers *(search)* |
| crates.io | Yanking, trusted publishing | Apache-2.0 / MIT | Active (2026-11-22) | A model for Withdrawal semantics: yanked versions are still fetchable by existing lockfiles. The ADR instead blocks new fetches. | **Prior art only** | github.com/rust-lang/crates.io |
| Homebrew taps | Catalogs that are Git repositories | BSD-2 | — | Comparable to Channel-as-repository. | **Prior art only** | docs.brew.sh |

**Should SkillDeck federate instead of building a catalog?**

- **Inbound:** already covered. Git, well-known and marketplace.json Sources install any external catalog without a SkillDeck catalog.
- **Outbound:** cheap and useful. Export public Releases as an Agent Skills discovery index.
- **What still has to be built:**
  - Grants, private Sharing, Teams, Withdrawal, required signatures and moderation. No external registry offers per-person or per-team Grants on top of our identity.
  - Phase 4 can start as "Public Grant plus Listing plus well-known export", with Ratings and search added as demand appears.

### 2.11 Marketplace search (Phase 4)

| Candidate | Covers | License | Maintenance | Fit | Verdict | Source |
| --- | --- | --- | --- | --- | --- | --- |
| D1 FTS5 | Full-text search inside the same database | Platform | D1 can export virtual tables since 2026-11-12 (dump with `sqlite3_cli_only`; it cannot be re-imported into D1) | Enough for a first public catalog. Use the trigram tokenizer for Chinese substrings, which needs at least 3 characters, so two-character Chinese terms will not match: a gap for the zh locale. | **Adopt** (Phase 4 start) | developers.cloudflare.com/d1/best-practices/use-indexes/; changelog/d1/2026-11-12 |
| Vectorize with Workers AI embeddings | Semantic search. `@cf/baai/bge-m3` is multilingual ($0.0118 per million tokens); `@cf/qwen/qwen3-embedding-0.6b`; `@cf/google/embeddinggemma-2` | Platform | Vectorize allows 1,536 dimensions and 20 M vectors per index | Add once the catalog is large. bge-m3 covers en and zh. | **Adopt partially** (later) | developers.cloudflare.com/vectorize/platform/limits/; Workers AI model catalog |
| Meilisearch | Hosted or self-hosted search | MIT core; **Enterprise Edition under BSL 1.1** | v1.57.0, 2026-11-12 | Another service to run. Avoid Enterprise Edition features. | **Reject** (for now) | github.com/meilisearch/meilisearch |
| Typesense | Self-hosted search | **GPL-3.0** (server) | v30.2, 2026-04-09 (latest tag found) | Acceptable for a private service (no network clause), but another service to run. | **Reject** (for now) | github.com/typesense/typesense |
| Algolia | Managed search | Proprietary | **UNVERIFIED** | Lock-in. China reachability unknown. | **Reject** | — |

### 2.12 Moderation and abuse (brief)

- **Build the Reports queue and Withdrawal in D1.** The domain rules are already specific, and no adoptable product fits.
- **Workers AI `@cf/meta/llama-guard-3-8b`** can serve as an advisory safety classifier on Listing text and SKILL.md. Use it as a signal, not an authority. Llama Guard classifies safety categories and does not detect prompt injection.
- **Copy the pre-publish checks seen elsewhere:**
  - Open VSX: impersonation, secret and malware checks with quarantine, failing closed;
  - skills.sh: partner audits, with Socket and Snyk named in third-party reports *(secondary)*.
- **Never execute Skill content** during scanning (repository invariant).

### 2.13 Phase 5 entitlement and payments (brief)

| Candidate | Merchant of record? | Notes | Verdict | Source |
| --- | --- | --- | --- | --- |
| Paddle | Yes | Common for desktop software and handles global VAT. No Better Auth plugin in the docs tree. | Candidate | — (**UNVERIFIED** details) |
| Stripe Managed Payments | Yes, through "Sold through Link, LLC" | Reported GA in April 2026 *(secondary)*. Better Auth has an official `@better-auth/stripe` plugin (1.7.27). | Candidate | support.stripe.com *(search)*; npm |
| Lemon Squeezy | Yes | Stripe-owned. Its 2026 update steers customers to Stripe Managed Payments *(secondary)*. | **Reject** (migration risk) | lemonsqueezy.com/blog/2026-update *(search)* |
| Polar | Yes | Open source (Apache-2.0), has license-key and benefit primitives, and has a Better Auth plugin. | Candidate | github.com/polarsource/polar; better-auth docs/plugins/polar |

Keep entitlements server-authoritative in D1 and keyed by Cloud Account, with the payment provider behind a port. Better Auth also documents Creem, Dodo Payments and Commet (all merchants of record) and Chargebee/Autumn plugins. Choose only when Phase 5 is active.

### 2.14 Cross-cutting checks

- **Licenses:**
  - All recommended client dependencies are BSD-3, MIT or Apache-2.0, apart from `win_http` (GPL-3.0, compatible).
  - Flags for the service: Couchbase (BSL 1.1), Meilisearch Enterprise Edition (BSL 1.1), Forgejo (GPL-3.0-or-later), Typesense (GPL-3.0).
  - No AGPL, SSPL or ELv2 dependency is in the recommended stack.
- **Mainland China:**
  - The Cloudflare China Network requires an **Enterprise plan plus an ICP filing or license**.
  - Its developer-services list includes Workers, KV, R2 (with restrictions) and Workers for Platforms. It does **not** list D1, Durable Objects or Artifacts (as of 2026-11-22).
  - Pages is explicitly unavailable.
  - Mainland users would reach the global network. Whether `*.artifacts.cloudflare.net` and the API are reachable or usable there is **UNVERIFIED**.
  - GitHub sign-in from China is **UNVERIFIED**, so email OTP is the safer path.
  - Google and Firebase are reported blocked *(secondary)*.
  - Source: developers.cloudflare.com/china-network/reference/available-products/.
- **Lock-in and export:**
  - Artifacts holds plain Git, so `git clone --mirror` with a read token exports everything.
  - D1 offers SQL export, including virtual tables since 2026-11-12.
  - Better Auth tables live in our D1 under the MIT library.
  - Durable Objects hold only ephemeral connection state in this design.
  - Keep Git remotes server-issued per operation, never in descriptors. A move to another Git host is then a server-only change.

---

## 3. Recommended stack

### Phase 1: Personal Sync (detail)

**Adopt, on the client (`skills_cloud` stays pure Dart; the App injects platform clients):**

1. **HTTP:**
   - a `package:http` `Client` seam;
   - **`cupertino_http`** on macOS;
   - on Windows, **qualify `win_http`** with the prototype's stalled-TLS probe (`tool/qualify_tls_cleanup.dart`), then depend on it, vendor it, or write a minimal WinHTTP FFI client;
   - `IOClient` with hard deadlines on Linux, which is best effort;
   - keep the prototype's transport bounds and redaction.
2. **Secure storage:** the existing `flutter_secure_storage` holds only the Cloud Session.
3. **Realtime:**
   - **`package:web_socket`**: `CupertinoWebSocket` on macOS, and `IOWebSocket.fromWebSocket` over dart:io on Windows (or WinHTTP's WebSocket API if the stalled-TLS problem also affects WebSocket connects; **UNVERIFIED**);
   - our own reconnect supervisor with full-jitter exponential backoff, a connect deadline and protocol pings;
   - every (re)connect triggers Reconciliation.
4. **Git:**
   - keep libgit2;
   - pass the Artifacts token through the per-operation callback, as a Bearer header or as Basic auth with the secret before `?expires=`;
   - never persist the remote URL or token.

**Build, on the client:**

- **Sign-in:**
  - email OTP in-app (send OTP, verify, read `set-auth-token`);
  - GitHub through the system browser (`url_launcher`) and the prototype's PKCE loopback handoff;
  - RFC 8628 device flow as fallback.
- **Reconciliation:** ancestry comparison through the R11 seams.
- **Metadata compare-and-set client** and Note Conflict handling.
- **Own credential-free SQLite store** for lineage mapping, Device Exclusions, the feed cursor and Field Versions.
- **Sync Status derivation**, covering every Attention Reason.

**Adopt, on the service:**

- **Workers with Better Auth 1.7.x** on native D1 (`database: env.DB`), with the plugins `emailOTP`, GitHub social, `bearer` and `deviceAuthorization`, and session management for per-Device revocation. Configure `cf-connecting-ip` and use no KV secondary storage.
- **Cloudflare Artifacts:**
  - one namespace per environment, with the **jurisdiction decided before creation** because it is immutable;
  - one repository per Lineage Generation;
  - `createToken('write', ttl≥60s)` only for the owning account's Device, and `read` for fetch;
  - revoke tokens after Head Advance (token operations cost 0.2 operations each).
- **Durable Objects:** one per account, hibernatable WebSocket, ping after each D1 commit. PartyServer is optional.

**Build, on the service:**

- **Head Advance:**
  - first check that the new commit exists (`repo.readCommit(hash)`);
  - then check that it descends from the expected head by walking parents;
  - then do a compare-and-swap with one conditional `UPDATE … WHERE effective = :expected`, since D1 has no interactive transactions.
- **Field Version compare-and-set** and the tag-vocabulary rules.
- **Account Change Feed:** latest entry per entity.
- **Grace and tombstone jobs** and retention-ref cleanup.
- **Push events** used only as asynchronous audit and GC hints, never as the commit point.

**Why:** every adopted piece is thin and replaceable, and none of them can write Workspace state. Everything that encodes SkillDeck semantics (Head Advance, compare-and-set, the feed, Attention Reasons) is small and specific, and no adoptable engine matches it.

### Phase 2: Individual Sharing

- **Channel repositories in Artifacts, with protected refs approximated by custody:**
  - clients never receive Channel `write` tokens;
  - the publisher pushes the Release commit to a staging location (for example its own Lineage Repository under a retention ref);
  - a Worker verifies that the tree matches the manifest and that the parent is the previous Release;
  - the Worker then copies the commit into the Channel repository with isomorphic-git and a server-held token;
  - recipients get `read` tokens only after a Grant check.
- **Releases** record the manifest digest. Whether Sharing Releases are also signed is the ADR's open question.

### Phase 3: Team Distribution

- **Better Auth `organization`:** map Owner/Publisher/Member to owner, a custom role and member through `createAccessControl`, and use its invitations.
- **Build** the last-Owner rule and Team audit history in D1.

### Phase 4: Public Marketplace

- **Publisher signatures:** Ed25519 keys in platform secure storage sign the canonical Release Manifest. The service adds a TUF-style signed, versioned and expiring snapshot of the public index to prevent rollback.
- **Search:** D1 FTS5 first, then Vectorize with bge-m3.
- **Build** Listings, Ratings, Reports and moderation, with Llama Guard as an advisory classifier.
- **Federation:** export public Releases as an Agent Skills discovery index (`archive` entries with `sha256` digests) and optionally as a `marketplace.json`.

### Phase 5: Entitlement and payments

- Choose a merchant of record: Paddle, Polar or Stripe Managed Payments.
- Keep entitlements in D1 behind a provider port. Better Auth has Stripe and Polar plugins.

---

## 4. Risks and unknowns

### Could not verify (needs a qualification test or vendor confirmation)

- **Artifacts behavior:**
  1. Is a force-push or ref deletion with a `write` token accepted? Assumed yes, as standard receive-pack.
  2. Does it GC unreachable objects, and when?
  3. Does it allow fetching by an unadvertised SHA?
  4. Does `readCommit` metadata include parent IDs? The generated types are authoritative.
  5. Is there any anonymous read or custom Git domain?
  6. Is there an open-beta SLA?
  7. What is the exact billing start date (2026-10-14 or 2026-11-19)?
- **libgit2 and Artifacts interoperability:**
  - push over receive-pack v1, with many `refs/retain/*` updates per push (limit 1 MiB);
  - fetch without `filter`/`include-tag`;
  - how errors are redacted.
- **Mainland-China reachability** of `*.artifacts.cloudflare.net`, the Workers API, the Durable Object WebSocket and GitHub OAuth. Delivery of OTP email to Chinese providers.
- **`win_http`:**
  - whether it is GPL-3.0-only or GPL-3.0-or-later;
  - whether its abort actually reclaims sockets during a stalled TLS handshake;
  - whether the same SDK limitation affects dart:io WebSocket connects on Windows.
- **Whether `CupertinoWebSocket` can send custom headers.** If not, authenticate with a short-lived ticket in `Sec-WebSocket-Protocol` or in the first message, never the session token in the URL.
- **Whether `@better-auth/electron` accepts a loopback (`http://127.0.0.1:<port>`) redirect** instead of a custom scheme.
- **Secondary-source items:**
  - the GA date of Stripe Managed Payments;
  - Lemon Squeezy's migration;
  - Firebase being blocked in China;
  - skills.sh audit partners;
  - details of Freestyle and Code Storage.

### Decisions for the maintainer

1. **Accept Artifacts' open-beta status** as the Phase 1 Git host, with Containers plus Soft Serve or Forgejo as the documented exit. Choose the namespace jurisdiction (EU, US or unrestricted) before the first repository, because it cannot change.
2. **Protected-ref strategy for Channels:** server-side copy by token custody (recommended) or a self-hosted Git server with hooks.
3. **Retention-ref and object GC:** client cleanup push, a server push through isomorphic-git, or accepting accumulation until Artifacts documents GC.
4. **Windows networking:** adopt `win_http` (GPL-3.0, single maintainer), vendor or fork it, or write our own WinHTTP FFI. Also choose the Windows WebSocket path.
5. **Primary desktop sign-in:**
   - PKCE loopback with a small custom Better Auth endpoint (recommended);
   - a custom scheme with `app_links` and the electron plugin;
   - or device authorization as the primary path.
6. **Mainland China:** support it properly (Enterprise China Network, ICP, and a non-Artifacts Git path for China) or treat it as best effort (open issue 02).
7. **Signing:** publisher key custody, recovery and rotation, and whether Sharing and Team Releases are signed (ADR open question).
8. **Phase 4 scope:** federate first (Public Grant, Listing and well-known export) or build full search and Ratings at launch.
9. **Phase 5:** which merchant of record, and whether licenses need offline validation.
