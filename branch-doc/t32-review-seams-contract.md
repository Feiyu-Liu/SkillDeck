# T32 Workspace review interfaces

The maintainer approved these two public Workspace capabilities on
2026-11-27. The App reaches them through its current repository. Cloud owns
the HTTPS requests and temporary downloaded pack.

## Review a pending Revision Pack

`SkillsRepository.inspectRevisionPackDiff(InspectRevisionPackDiffRequest)`
returns `SkillsOperation<RevisionPackDiff>`.

| Request field | Type | Meaning |
| --- | --- | --- |
| `managedSkillId` | `ManagedSkillId` | The existing local Skill |
| `expectedEffective` | `RevisionId` | The local Effective Revision returned by `inspectRevisionSelections` |
| `incomingEffective` | `RevisionId` | The incoming Effective Revision |
| `incomingUpstream` | `RevisionId?` | The incoming Upstream Revision, absent for Skills without one |
| `packPath` | Absolute local file path | A caller-owned Revision Pack file |

`RevisionPackDiff` contains `managedSkillId`, `from` and `to` as
`RevisionId` values, and a list of the existing `SkillFileDiff` model.
The current `SkillDiff` requires published operation subjects. A pack
behind a Draft has no such subject. Reuse the file, hunk and line models.

Workspace acquires a read lease over the local selection, checks
`expectedEffective`, verifies the pack and all supplied incoming roots in
isolated staging, and compares the local and incoming Effective trees. A
null Upstream skips validation of that root. Include
additions, deletions, renames and binary files. Release the lease and remove
scratch files on success, failure or cancellation. The operation has no
business commit point. It leaves the live Revision Store, Effective
selection, Draft, operation history and Activations untouched.

Use `skillNotFound` for an absent Skill, `staleSnapshot` for a changed
Effective Revision, and `archiveInvalid` for an invalid pack or missing
incoming root. Use the existing `revisionStoreCorrupt`,
`operationCancelled` or `ioFailure` codes for corresponding local failures.

The Reconciler reads the linked Lineage and fetches the pack for that Head.
It passes the pack file and opaque Revision IDs through the adapter. The
result identifies the selections that were compared even if a later Feed
Check observes another Head.

## Resolve Update Candidate conflicts using one side

`SkillsRepository.inspectUpdateCandidateResolution(ManagedSkillId)` returns
`SkillsOperation<UpdateCandidateResolutionReview?>`. It returns null when
there is no candidate. The review contains the `UpdateCandidateSummary`
and an opaque Workspace review token. The token is scoped to the open
Workspace and Skill and binds the candidate identity, merge inputs,
conflict states and observed Draft fingerprint. Obtain a fresh review
after a change or process restart.
An absent Skill returns `skillNotFound`. A changed selection returns
`staleSnapshot`. An unreadable Store or Draft returns its typed local
failure.

`SkillsRepository.resolveUpdateCandidateConflicts(
ResolveUpdateCandidateConflictsRequest)` returns
`SkillsOperation<RepositorySnapshot>`. Its fields are
`managedSkillId: ManagedSkillId`, the opaque review token, and
`side: UpdateCandidateSide.current | UpdateCandidateSide.incoming`.
`current` selects the previous Effective bytes. `incoming` selects the
incoming merge input. The existing per-file request marks a path resolved
without changing candidate bytes, and the current summary lacks a token.

Under the Workspace writer lease, revalidate the token and candidate,
conflict and Draft evidence. Resolve every still unresolved conflict by
choosing the same side's file content, deletion, rename placement and
executable mode. Copy binary bytes verbatim. Preserve already resolved
paths and nonconflicting merge results. Build the next candidate Draft
in staging and commit its changes and conflict statuses together in the
Workspace transaction. Keep the selected executable intent in the candidate
base so it can be published on a host without POSIX mode bits. Fail the whole
set when a choice cannot be applied safely. Use the normal finalization-pending
result if post-commit work needs recovery.

Return `skillNotFound`, `staleSnapshot` for a foreign or stale review,
`externalConflict` for a set that cannot be materialized safely, and
the existing cancellation, I/O or corruption codes as applicable.
When there are no unresolved paths, a still-current review returns the
unchanged snapshot. A changed Draft still invalidates that review.
The side shortcut leaves the resolved Draft available for review.
`publishUpdateCandidate` remains a separate explicit user action and uses
the current validation and publishing transaction.

## Acceptance

- A pack diff behind a Dirty Draft compares the selections and leaves the
  full Workspace state intact. Cover rename, deletion, binary files, stale
  Effective selection, invalid pack and staging cancellation.
- Cover each shortcut with conflicting text, rename, delete/modify, binary,
  and executable mode. Confirm that nonconflicting and resolved files
  survive and the separately published candidate has the selected content.
- A changed candidate, conflict state or Draft invalidates its review.
  Exercise a filesystem change after preflight and failures on both sides
  of the transaction commit point.
- Two App runtimes converge to Synced after resolving and publishing a
  Sync Merge conflict.
