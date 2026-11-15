# skills_cloud

Pure Dart Personal Cloud authentication, durable Sync coordination and wire protocol code. This package
does not import Flutter, Skill Workspace, Git storage or App state. Its optional
SQLite adapter owns a physically separate, credential-free Cloud database. Its
normal public surface is `package:skills_cloud/skills_cloud.dart`; production
code lives in `lib/src/`. It requires Dart 3.13 or newer.

## Authentication composition

Construct `HttpsCloudTransport` with the trusted HTTPS service origin and
`CloudAuthClient` with that transport, a `SecureSessionStore`, and a
`launchBrowser(Uri)` callback that opens the system browser. No application
credential is included in a browser URL. Login uses S256 and unguessable state,
binds a real `127.0.0.1` ephemeral listener, opens only the exact configured
service's handoff URL, validates callback Host/path/state/duplicates, and
exchanges the one-use code over HTTPS. Success, timeout and cancellation close
the listener.

The exchanged credential is verified through `/v1/session` before one complete
`SecureSessionRecord` is atomically written and a safe `CloudSession` is
published. That record binds the credential to its exact `serviceOrigin` and
account/device/session IDs. Restore verifies the origin before attaching the
credential, then verifies the full identity with the server. Renewal belongs to
the server and retains the same session identity; there is no invented rotating
access/refresh protocol or local-expiry guess.

The App implements `SecureSessionStore` using platform secure storage. Encode
`record.toSecureJson()` into **one atomic secure value**, never SharedPreferences,
SQLite, files, revision configuration or operation records. Every mutation of
this store is serialized by the auth client. A delayed old write cannot follow
a successful logout clear, and old cleanup cannot clear a newer login.
`CloudCredential`, records, requests, responses and domain wrappers redact their
`toString` output. Raw storage/provider exceptions are never retained as causes.

Authentication transitions stop existing requests and reject new authorized
requests until verification and secure persistence finish. `CloudAuthLease`
binds asynchronous work to the owner, epoch and identity. Sync captures it
before awaiting durable storage and checks it again before sending and before
reporting success. An old payload never receives a newly signed-in account's
credential.

`logoutCredentials()` stops requests and clears only credentials. It leaves
Sync data, intents and recovery policy to App composition. Device list/revoke
uses verified bearer authorization; self-revocation also clears the local
credential. `pending:true` reports incomplete remote provider-token cleanup.

## Durable operation contract

`CloudSyncClient` supports typed preparation/commit requests, changes, immutable
snapshot pages and read-only operation recovery. Sync GETs carry exactly one
`protocolVersion=1`; POSTs use the version/requestId/data envelope. Decimal
sequences use `CloudSequence`/`BigInt` through the full D1 signed 64-bit range.
Global personal-tag changes have genuinely null lineage/generation and are a
separate typed union member. Snapshot vocabulary retains unassigned tags.
Metadata patches preserve omission, null, false and empty string independently.
Source descriptors retain their complete versioned provenance.

Use `createIntent`/`createPrepareIntent`/`createCommitIntent` only for genuinely
new intentions. Fresh unsent intentions can remain offline indefinitely: the
first successful durable CAS immediately before sending starts their 24-hour
window. `CloudMutationIntent.restored` never treats a missing origin as new.

The App composes `SqliteCloudDatabase` or supplies `MutationIntentStore` with an authoritative account/device
scope, `readOperation` and atomic `compareAndSet`. CAS must check the scope is
still authoritative in the same transaction as its write. Scope metadata must
survive restart and must not become ready merely because a database is absent.
A newly minted server device from successful **signIn** can establish a new
scope explicitly. Restoring an old secure session after losing/resetting its
operation database requires reconciliation. Do not reconstruct an uncertain
old operation with the fresh factory or a new operation ID.

The persisted account/device/operation record owns the earliest first-send
time, last clock observation, business family, endpoint-bound immutable payloads
and the returned preparation upload ID. Prepare and first commit share that
origin; a first commit requires the persisted matching preparation/upload.
Other cross-family operation-ID reuse is rejected. At exactly 24 hours, on
observed backward clock motion, missing origins or unavailable durable storage,
the client returns `needsReconciliation` without sending. HTTP is never retried
automatically and operation IDs are never replaced. Read-only status/changes
and snapshot APIs support later reconciliation without claiming noncommit.

## HTTPS runtime boundary

Requests always require HTTPS, preserve TLS/hostname verification, disable all
redirect following, bound request and streaming response bytes, and impose a
total deadline over connection, headers and body. Invalid UTF-8/JSON is a
non-retryable `invalidResponse`. A trusted optional `SecurityContext` can add
explicit CA trust without disabling certificate verification. Tests use a
temporary local CA/leaf certificate; no global trust setting is changed.

**Measured Dart 3.14 limitation:** a TCP connection whose TLS peer never finishes
its handshake can outlive `HttpClient.close(force:true)`. The client returns its
timeout/cancellation promptly and never sends an HTTP authorization header
before TLS completes. Four unfinished opening futures are tracked across
transport instances in the isolate; further opens fail closed until the actual
futures settle. Reconstructing the transport does not reset this bound. Native
physical socket reclamation is not claimed. `tool/qualify_tls_cleanup.dart`
reproduces that platform limitation independently and currently exits 2 with
`knownSdkLimitation`; it is not part of the passing unit suite. No handwritten
TLS, private SDK calls or insecure HTTP escape hatch is used.

## Verification

Run from this package:

```sh
PUB_HOSTED_URL=https://pub.dev dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart test --coverage=coverage
dart run coverage:format_coverage --packages=.dart_tool/package_config.json --lcov -i coverage -o coverage/lcov.info --report-on=lib
dart run tool/qualify_tls_cleanup.dart
```

`test/fixtures/sync-contract.json` pins 40 actual version-three service cases,
SHA-256 `80e009e0fb5661dbca1568beb0c71a913c634cd6bfeef08f13ee997a8adac3fa`.
Typed requests preserve full source provenance, upstream/effective roots, distinct
published events and canonical microsecond timestamps. The fixture includes
replacement and repair, global vocabulary, explicit clear patches, large decimal
sequences and pagination. Slot fixtures use actual Workspace derivation outputs,
including valid 255-character truncation-boundary punctuation.

## Durable Sync

`CloudSyncCoordinator` accepts only an explicitly initialized selection. Whole
changes pages, snapshot traversal bounds, inbox rows and received cursors share
one transaction. Snapshot creation owns a durable request key before its first
HTTP call; a lost response or restart reuses the same frozen snapshot. Catalog
snapshots are disposable and explicitly released; bootstrap releases only after
all pages have been durably staged. This works with one active snapshot per
device. Received and applied progress remain separate, with bounded inbox,
page-replay and terminal-proof retention.

Content, fields, assignments and global vocabulary have separate durable steps.
The coordinator admits at most four independent preparation jobs and serializes
local mutations. The App's native adapter currently serializes its public-port
operations because an authoritative-ready Workspace capture excludes active
network transfers. This is a performance limit, never permission to weaken
absence, recovery or finalization checks.

Native applies persist the receiver operation, native request fingerprint,
receiver target and local-lineage binding before mutation. Unknown results use
the public caller-outcome seam after restart. Equal content cannot acknowledge an
unknown native operation. Fresh exact-root linking can prove desired state only
when history is already present; missing remote history goes through a real
Workspace history-import transaction. A persisted pre-existing-target marker
protects local Extra Data across either path and across acknowledgement loss.

Outbound tasks retain the original desired payload and operation ID. Original
receipt acknowledgement, baseline and exact sequence/kind/payload echo are one
transaction. Later local edits need a new operation after the original settles.
Old receipts cannot roll back a newer generation, Note or retired tag. Receipt
payload conflicts remain pending. Pausing never clears a reconciliation fence.
Cloud integrity events record `stateObserved` separately; `repairReady` can
unblock missing content without claiming that a Workspace operation executed.
Repair reuploads only exact selected roots/history and never creates a Publish.

The independent development schema v2 rejects foreign or incomplete databases;
its v1 migration preserves operation rows atomically. Actual SQLite tests cover
rollback, reopen/loss, actor/origin/Workspace isolation, immutable origins,
writer contention across eight isolates, and read-only startup probes. Missing
or corrupt authority is retained and fenced, never silently recreated by restore.

The service-side metadata rule remains server-acceptance-order LWW. A client
with an unsent local Note/Favorite/assignment differing from the confirmed
baseline cannot yet settle competing publication order automatically. It keeps
the local edit and leaves the affected atomic patch pending instead of erasing
or blindly uploading either side. Unknown initial metadata protects non-default
local edits; same-target no-op results still require real native proof. Pending
vocabulary blocks vocabulary publication using complete SQL existence checks,
so a same-name/different-ID tag is never merged or duplicated automatically.
Explicit local removal/replacement can retire older non-unknown conflicts.

## Qualification boundaries

Unit tests use actual SQLite connections, temporary verified local CA/leaf TLS,
loopback sockets and injected secure-storage/mail ports. The companion App tool
`skilldeck-app/tool/cloud_single_skill_integration.dart` is now a multi-Skill
qualification runner. From the service checkout run
`npx tsx scripts/dev-auth/run-full-cloud.ts` against the integration App checkout.
It uses the real service, local D1, actual OTP/S256/loopback handlers, public
Workspace operations and native Git transfers. Credentials cross only dedicated
RAM FIFOs. No deployed service, real email, user Keychain or user Workspace is
used. Final cross-repository evidence belongs to the service's
`evidence/integration/full-cloud-final.json`.

That chain covers batch opt-in, snapshot response loss/restart, exact roots and
history, independent initial-history union and a subsequent real Publish,
metadata/assignment/vocabulary, acknowledgement loss with later local edits,
Dirty Draft isolation across two Skills, guarded replacement/removal, and exact
selected-object repair after a real retention-ref loss. Independent installation
history uses controlled public-incoming source fixtures; it is not ordinary
original-source online acquisition acceptance.

The App's secure-storage adapter is tested through injected storage only.
Widget-rendered images and a macOS debug build do not establish installed App,
user Keychain, production mail/TLS, Windows/Linux SDK runtime, deployment or
release acceptance. The separate TLS cleanup qualifier above still reports the
known Dart SDK physical-socket limitation; prompt cancellation and the global
pending-opening cap do not claim physical handshake-socket closure.
