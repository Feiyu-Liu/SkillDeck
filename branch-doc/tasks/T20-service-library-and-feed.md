# ExecPlan: T20 Service: Lineages, Cloud Library, ending, and the feed

Milestone M4, service side, part 1 of 2. **Runs in the private service
repository.** The maintainer copies this card and `../cloud-api-contract-v0.1.md`
into that repository; Codex keeps the maintained sections of that copy.
T21 builds packs and Head Advance on top of this card. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

On dev, the service holds per-account Cloud Lineages in account-sharded D1.
It answers the contract v0.1 endpoints that do not move content:
- list the library;
- read and create a Lineage;
- Synced Removal and Stop Syncing;
- the Account Change Feed.

Each head records the Device that made it, so the session must keep its
Device description.

### Context

- **Read first:** contract v0.1 in full, contract v0 (conventions, sessions,
  429), and the T17 code. This card extends T17's Worker, D1 setup, and
  sign-in.
- **The prototype** is `spikes/revision-pack/` on branch
  `spike/revision-pack-prototype`, with its report on the SkillDeck branch.
  Its schema, CAS pattern, and harness may be reused. Its stub auth must not
  be.
- **Decided 2026-11-27:** D1 is sharded by account from the start.
  - Every query of an account's Lineages, Commit Graph, and feed touches
    exactly one shard.
  - How an account maps to a shard is your choice: for example one database per
    account, or a fixed set chosen by a stable hash. Record it in the Decision
    Log, with what adding shards later would take.
  - Workers Paid includes 100,000 D1 databases. One database holds at most
    10 GB and runs one query at a time.
- **Better Auth sessions** come from T17. T17 stores the Device description on
  the device-code row and drops it when the code is consumed. `head.device`
  needs it on the session.

### Contract

- **Endpoints, exactly as contract v0.1 specifies:**
  - `GET /v0/library`;
  - `GET /v0/lineages/{id}`;
  - `POST /v0/lineages`, with `clientKey` retained for 30 days;
  - `POST /v0/lineages/{id}/removal`;
  - `POST /v0/lineages/{id}/stop`;
  - `GET /v0/feed`, including `410 cursorExpired`.
- **The Lineage object:** every field. `head` stays `null` until T21's Head
  Advance writes it.
- **Writes:** every write that changes a Lineage increases its `version` and
  moves its feed entry in the same D1 transaction or batch.
- **Sessions:** when a session is issued, store the Device name and platform
  from its device code with the session, so T21 can fill `head.device`. A
  session from before this change has no description; its heads report the
  name as `null`. Record that in the Decision Log.
- **Retention:**
  - a Lineage created but never advanced is removed after 24 hours;
  - a tombstone stays readable for 90 days, then goes, with its feed entry;
  - the feed then answers `cursorExpired` to cursors older than what it
    dropped.

  These run as a scheduled sweep, with the times as configuration, so tests can
  shorten them.
- **Errors:** as the contract lists them. Another account's Lineage is the same
  404 `notFound` as a missing one.
- **Logs:** no tokens, `source` contents, declared names, or Device names.

### Acceptance

Tests in the Workers runtime against local D1, as in T17.

- **Shape:** each endpoint's method, path, status, fields, and errors match the
  contract. This includes the paging of the library and of the feed.
- **`clientKey`:**
  - repeating a create with the same key returns the same Lineage;
  - the same key from another account creates a separate Lineage;
  - after the configured retention, the key no longer matches.
- **Ending:**
  - removal and stop each set `state`, clear `head`, and increase `version`;
  - repeating the same end answers 200;
  - the other end answers 410 `lineageEnded`.
- **Feed:**
  - one entry per Lineage, ordered by commit;
  - an empty Feed Check returns `entries: []` with the same cursor;
  - `more` pages correctly;
  - an unknown `after` and an expired cursor each answer as the contract says.
- **Bootstrap:** a change committed while the library is being paged is
  returned by the feed read from the listing's `feedCursor`.
- **Sharding:**
  - two accounts on different shards never see each other's data;
  - a test fixture with at least two shards shows one account's requests
    touching one shard only.
- **Sessions:** a session issued through T17's device flow carries its Device
  description, and nothing else about the device code.
- **Sweep:** with shortened times, it removes an unadvanced Lineage, an
  expired tombstone, and its feed entry.
- **No leaks:** a log-capture test over the flows above finds no token, email,
  `source`, declared name, or Device name.
- **Gates:** the repository's format, typecheck, tests, and build, each with its
  own exit code, and all T17 tests unchanged.

### Scope fence

- **Out of scope:**
  - packs, Head Advance, and Generation change (T21);
  - metadata and tags (v0.2, M6);
  - deploying;
  - the legacy Sync API (T17-5);
  - changing the contract. Propose a change instead.
- **Expected size:** about 15–25 files, 1,500–2,500 lines including tests.

### Stop and ask if

- Sharding by account needs a Cloudflare product beyond Workers, D1, and Cron
  Triggers.
- The feed cannot keep one entry per entity in the same transaction as the
  write.
- Keeping the Device description on the session needs a Better Auth patch.

## Maintained by Codex

Kept in the service repository's copy of this card.
