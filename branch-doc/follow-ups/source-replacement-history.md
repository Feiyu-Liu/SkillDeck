# Follow-up: preserve history when accepting a remote source replacement

Status: needs an engine contract; not part of T43.

The maintainer approved separating this on 2026-11-28. T43 keeps existing
replacement behavior and explicitly warns that the device's unsynced revisions
and previous history are removed and replaced by the new source's history.

Desired outcome: accepting a new source should preserve the prior local
revisions in history, without changing the selected new source or uploading
private old history to a distribution channel.

Before implementation, decide how history from multiple source generations is
presented, retained, exported, and removed. Do not add a Cloud-specific concept
to Workspace. Test actual history reads after replacement and crash recovery.

Current evidence: `WorkspaceSyncAdapter.replaceSource` calls
`RemoteSkillSourceReplacement`; `prepareRemoteSourceReplacement` prepares a new
store; `DestructiveOperationPlanner.planPreparedSourceReplacement` deletes old
Source Lineages and retains operation subjects only for the new lineage.
