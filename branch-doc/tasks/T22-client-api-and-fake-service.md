# ExecPlan: T22 Client: contract v0.1 API client and an in-memory fake service

Milestone M4, client side, part 1 of 3. Implements the client side of
`../cloud-api-contract-v0.1.md` in `packages/skills_cloud/`. T23 and T24 build
on it. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can call every contract v0.1 endpoint with typed results. An
in-memory fake service follows the same contract, so T23 and T24 can test
Reconciliation without a server.

### Context

- **Read first:** contract v0.1 in full; contract v0's conventions; and T16's
  code in `lib/src/sign_in/`.
  - **Origin and session:** `CloudServiceOrigin` and `CloudSessionStore`.
  - **HTTP status mapping:** 401 means sign-in required; 429 and 5xx mean
    `server`; anything else unexpected means `protocol`.
- **The service side** is T20 and T21, built in parallel. The fake is the only
  server this card and the next two use.
- **R16:** revisions are 40-character commit IDs that the client never parses.
  Packs are named by SHA-256.

### Contract

New public API of `skills_cloud`. Names may change; record why in the Decision
Log.

- **`CloudApi`:** built with an `http.Client`, a `CloudServiceOrigin`, and a
  `CloudSessionStore`.
  - It has one method per contract endpoint: list library, read Lineage,
    create Lineage, upload pack, download pack, Head Advance, Generation
    change, removal, stop, and Feed Check.
  - Each method returns a sealed result. The variants are the endpoint's
    success value, one variant per error code the contract lists for that
    endpoint, together with that error's extra fields, and the common account
    conditions.
- **Common account conditions:**
  - sign-in required: 401, after which the stored token is deleted, as in T16;
  - `storageLimitReached`;
  - unavailable, with T16's `CloudFailureCode`.
- **Feed Check:** its success carries the `Retry-After` delay, when the
  response has one.
- **Value types:** Lineage, LineageHead, LibraryPage, FeedPage, and FeedEntry,
  with an unknown kind kept as such and skipped by callers. A pack is named by a
  digest type.
- **Packs:**
  - upload streams a file and sets `Content-Length` and
    `SkillDeck-Pack-Roots`;
  - download streams to a file. It checks the SHA-256 while writing and deletes
    the file on a mismatch, which is a protocol failure.
  - `dart:io` is allowed in `lib/` for these pack files only. There is no
    `HttpClient` and no platform check.
- **`FakeCloudService`:** in-memory, behind an `http.Client` (`MockClient`).
  It implements every rule of the contract:
  - account isolation;
  - `clientKey`;
  - Head Advance's repeat check and rules 1–5;
  - Generation change;
  - ending;
  - one feed entry per entity, paging, and `cursorExpired`;
  - the 16 MiB bound.
  - **Test controls:** inject a failure, a lost response (commit, then fail),
    a 429 with `Retry-After`, and a clock for retention.
  - **Packs:** the fake cannot parse Git packs. It accepts a **fake pack
    encoding** instead: a small JSON document listing commits with their
    parents and file digests. T23's fake Workspace writes the same encoding.
    Pack Verification in the fake means:
    - the SHA-256 of the bytes;
    - the roots are present;
    - every listed parent is in the same document.
  - Export it from a separate library, `package:skills_cloud/testing.dart`,
    not from `skills_cloud.dart`.
- **Dependency:** `crypto`, at the version `skills_workspace` locks, for
  SHA-256. No other new runtime dependency.

### Acceptance

- **Request shape:** for each endpoint, a test checks the method, path, headers
  (Authorization only, pack headers), body, and that no token appears in a URL.
- **Results:** each documented error code maps to its own result variant, and
  extra fields such as the returned Lineage on `staleHead` are parsed.
- **Status mapping:** 401, 429, 5xx, a malformed body, and a connection failure
  map as in T16.
- **Packs:**
  - an upload streams the file without loading it whole;
  - a download with a wrong digest deletes the partial file;
  - an over-bound file is refused before sending.
- **The fake follows the contract:** a conformance test runs every rule of
  contract v0.1 against `FakeCloudService` through `CloudApi`. It covers each
  Head Advance rule, the repeat rules, `clientKey`, both ends, and Generation
  change atomicity. It also covers feed order, paging, the empty check, and
  `cursorExpired`, and bootstrap via `feedCursor`.
- **No leaks:** the `toString` of the new public types contains no token,
  `source` contents, or declared name.
- **Gates:** T16's gates from `packages/skills_cloud/`, each with its own exit
  code, and line coverage of the new files reported.

### Scope fence

- **In scope:** `packages/skills_cloud/`.
- **Out of scope:**
  - Reconciliation and any Workspace port (T23);
  - metadata and tags (v0.2);
  - the App;
  - persistence of sync state;
  - the real service.
- **Expected size:** about 12–20 files, 1,500–2,200 lines including tests.

### Stop and ask if

- The contract is ambiguous on a point a test needs. Name the point; do not
  guess.
- The fake would need to parse real Git packs.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
