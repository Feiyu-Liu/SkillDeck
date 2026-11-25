# ExecPlan: T14 Recovery Bundles that carry each retained revision's history

Milestone M5 follow-up. Fixes item T13-1 of `../reviews/2026-11-24-m5-review.md`.
Decision: build every Recovery Bundle with full history, and fall back to
roots-only when the Store lacks part of that history. Chosen by the maintainer
on 2026-11-25. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

After a Skill's revision Store is lost and rebuilt from its Recovery Bundle,
`exportRevisionPack` works again, also for a Skill whose history came from
another Device through `applyRemoteState`. Without this, such a Skill can no
longer upload, so it stops syncing.

### Context

- **Defect (T13-1):** Codex's probe on `06a9ce4`:
  1. fast-forward a Skill with `applyRemoteState` over a remote-only
     intermediate commit;
  2. lose the Store and reopen.

  Open succeeds and the Skill reports `recovered`. The intermediate commit is
  missing, and `exportRevisionPack` returns `revisionStoreCorrupt`.
- **Cause:**
  - T13 made the bundle's roots cover everything this Device's SQLite lists.
    A remote-only ancestor appears in no local record, so it is no root.
  - The roots-only native pack (`recovery_pack_create`) stores each root's
    commit and tree, not its parents.
  - Export walks history from the Effective and Upstream, so it needs every
    ancestor.
  - The same happens to T08's initial install bundle: it carries the donor's
    history, but the next operation on that Skill replaces it with a
    roots-only bundle.
- **Existing code to reuse:**
  - `RevisionRecoveryBundlePublisher.publish` in
    `lib/src/composition/revision_recovery_bundle_publisher.dart` already takes
    `includeHistory` and passes it to both the worker path and
    `RevisionEnginePort.createRecoveryPack`.
  - With `includeHistory`, native `create_pack` uses a revwalk. When an object
    is missing it returns the object failure, which surfaces as
    `RevisionEngineFailureCode.objectUnavailable`. See
    `revision_pack_export_command.dart` for the current mapping.
  - T08 already passes `includeHistory: true` from
    `remote_install_preparation.dart`.

### Contract

No public API, schema, native, or manifest-format change. The manifest's roots
stay as T13 defined them; only the pack carries more objects.

- **History:** every Recovery Bundle a mutation writes holds the full commit
  history of every root, as far as the live Store has it.
- **Fallback:** if building the history pack fails only because the live Store
  lacks an object (`objectUnavailable`), build the roots-only pack instead and
  continue. Any other failure stays a failure, as today.
  - This keeps working a Store that was itself rebuilt from a short bundle
    before this fix. Such a Store's export still fails; see the Scope fence.
  - Do not log or record paths or object IDs for the fallback.
- **One rule:** decide this in the publisher, so a caller cannot forget it.
  Remove the `includeHistory` parameter, or its non-default uses, where it
  becomes redundant, including T08's. Record the choice in the Decision Log.

### Acceptance

Each item is a test through the public API with a real Store, unless noted.

- **The T13-1 probe:**
  1. fast-forward a Skill over a remote-only intermediate commit;
  2. close, move the Store aside, and reopen.

  Then:
  - open succeeds and the Skill reports `recovered`;
  - `exportRevisionPack` succeeds;
  - Published History lists the same entries as before the loss.
- **Merge:** the same loss and reopen after a clean Sync Merge (`merged`)
  whose remote parent exists only in the pack. Export succeeds.
- **Install, then a local change:** `RemoteSkillInstall` from a pack with at
  least two donor commits, then one local publish, then the loss and reopen.
  Export succeeds. Before this fix the publish dropped the donor history.
- **Repeated loss:** lose and rebuild the Store twice in a row, with a
  mutation in between. Export still succeeds.
- **Fallback (may use internal types):**
  1. bring a Skill into the state that a pre-fix Workspace can hold: its live
     Store lacks an ancestor of the Effective, for example by writing a
     roots-only bundle with the native roots-only call, then losing the Store
     and reopening;
  2. run a mutation that writes a bundle, such as a publish.

  Then the mutation succeeds, and the next open after another loss succeeds.
  Export returns `revisionStoreCorrupt`, as before; report that in Surprises.
- **Content (may use internal types):** after a mixed sequence (install,
  publish, Restore Publish, a remote content apply, and a remote install),
  restore the live bundle into a scratch Store. Every commit reachable from
  the manifest's roots in the live Store is in the scratch Store.
- **Cost:** for one Skill with 50 publishes, report in Surprises:
  - the bundle size before and after this change;
  - the time of the 50th publish before and after.

  No threshold. This is for the maintainer.
- All existing crash, recovery, and bundle tests pass unchanged, or the
  Decision Log says why one changed.
- **Gates:** the T01 gates, including `dart pub get --enforce-lockfile` and
  `dart run tool/regenerate.dart` with a clean tree afterwards. Report each
  command's own exit code.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - native, schema, and manifest-format changes;
  - rebuilding existing Workspaces' bundles at open;
  - repairing a Store that already lost ancestors. That needs the revisions
    from the Cloud again, which is M7's concern;
  - changing what reference reconciliation retains;
  - the T09 Nits.

  Existing Workspaces get history bundles the next time a mutation writes a
  bundle for each Skill.
- **Expected size:** about 4–8 files, 150–400 lines including tests.

### Stop and ask if

- The history pack fails for a reason other than a missing object in a
  Workspace that opens today.
- An existing performance or timing test gets noticeably slower, or the
  50-publish measurement shows the publish time more than doubling.
- Restoring a history bundle needs a change to `recovery_pack_restore`, the
  verification step, or the manifest.
- A path writes bundles without going through the publisher.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
