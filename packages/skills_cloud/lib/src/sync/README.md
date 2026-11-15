# Durable selected Personal Sync coordination

This layer owns credential-free Cloud state in schema version 2. Migration
from an identified version 1 database preserves operation origins and phases.
A new or foreign SQLite database does not silently become an opted-in scope.
The scope binds origin/account/device to a public Workspace identity and
recovery incarnation. Explicit user-selected Cloud lineages/local Skills and a
ready authoritative capture are required; the initial cursor is exactly zero.
Only a complete staged bootstrap can move the received cursor to its server H.
Global personal tags are account vocabulary, independent of selected lineages.

Changes pages, every inbox row, and received progress commit in one transaction.
A traversal keeps its original high-water mark. Exact replay of a retained page
is a no-op; changed content conflicts. Sixty-four page digests and 1,024 stable
terminal proofs bound local replay evidence. These are local operating limits,
not the server's 24-hour mutation-receipt contract. Older repetitions cannot
reexecute effects; absent old evidence requires reconciliation. Applied rows at
or below the applied cursor are compacted. The retained pending/gap inbox has
10,000 rows, each page at most 2,000 items and 1 MiB; exceeding these budgets
produces explicit backpressure rather than pretending to receive the page.

Snapshots stage lineages and global tags separately. Until their final page is
persisted, no staged snapshot item is offered for application and received H is
not published. Expired partial snapshots can discard only that unapplied staging
set, preserving selection, mappings, outbox and existing proof records. A
completed bootstrap cannot be discarded through that recovery operation.

`CloudSyncCoordinator` prepares at most four independent lineage downloads at a
time and serializes actual local transactions with fresh capture preconditions.
Same-lineage and same-tag order is also checked by SQLite, not only task order.
A dirty lineage or unknown outcome stays pending while unrelated lineages and
vocabulary can apply; the global applied cursor never skips earlier pending
work. Legitimate local revision growth refreshes only the capture baseline;
it does not imply absence, apply completion or remote consent. Incarnation or
readiness changes fence further work and require reconciliation.

Every event receives a durable local operation ID, exact event fingerprint and
immutable prepared local target before crossing a mutable Workspace port.
Unknown-outcome state is persisted first. After a crash, the coordinator looks
up a caller-bound proof; it never treats equal hashes or a missing outcome as
success. An affirmative `CloudConfirmedNotStarted` allows the same binding to
prepare/apply later. Exact stable terminal proof replay is a no-op even if its
new authoritative capture has a later revision; it cannot rewrite a mapping
or revive later local lifecycle state. Target absence requires completed cleanup,
and supersession requires explicit retirement evidence. Source replacement,
metadata atomic-proof gaps, divergence and Drafts remain typed pending.

Outbox records are selected, immutable upload **candidates** only. They do not
publish, start HTTP retries or transmit. New install preparation, actual public
Workspace caller-outcome proof and real transfer-provider composition remain
separate adapter qualification. Workspace private databases, journals and Git
Stores are never imported by this package. Every App storage call uses the
background SQLite adapter; no token enters any of these tables.
