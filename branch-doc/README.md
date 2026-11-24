# branch-doc

Development documents for SkillDeck Cloud, kept on the
`claude/amazing-keller-unt4dd` branch only.

> **Never merge this folder into `main`.** Before merging this branch, remove
> `branch-doc/` from the merge (for example, delete it in a final commit on a
> copy of the branch, or exclude it when squashing). The branch itself is on a
> public repository, so anything here is publicly readable.

New development documents for this work go in this folder.

## Contents

| File | What it is | Status |
| --- | --- | --- |
| `0105-revision-2026-11-23-proposal.md` | ADR-0105 revision, R1–R17: Distribution model, state-based Personal Sync, Revision Packs, macOS first | Accepted 2026-11-23; ADR-0105 amendment still to be appended in the private docs |
| `cloud-build-vs-adopt-survey.md` | Build-vs-adopt survey for the client and the Cloudflare service | Reference; its Artifacts and WebSocket verdicts are superseded by R8 and R15 |
| `brief-revision-pack-prototype.md` | Brief for the Revision Pack prototype (tests P1–P10) | Handed over; results pending |
| `handover-phase1-git-hosting.md` | Handover for the Artifacts vs self-hosted Git comparison | Superseded by R15; kept for the record |
| `git-hosting-local-test-results-2026-11-23.md` | Local Git hosting test results | Input to R15 |
| `windows-http-test-plan.md` | Windows HTTP qualification plan | Paused (R17) |
| `windows-http-2026-11-23.md` | First Windows HTTP qualification run | Input to R17 |
| `execplan-template.md` | Template for the ExecPlans handed to Codex, with simplicity rules against over-engineering | Draft |
| `phase1-plan.md` | Phase 1 (Personal Sync, macOS) plan: goal, binding decisions, components, milestones M1–M8, blockers | Draft |
| `tasks/T01-revision-pack-export.md` | Seam 1: Revision Pack export and the public revision identifier (R16) | Implemented and verified locally |
| `tasks/T02-revision-pack-import.md` | Seam 2: Revision Pack import into staging | Implemented and verified locally |
| `tasks/T03-synced-origin-source.md` | Seam 5: Synced Origin Source descriptor, schema v4 | Implemented and verified locally |
| `tasks/T04-skills-cloud-package-and-feed-check.md` | New `skills_cloud` package and Feed Check scheduling (R8) | Implemented and verified locally |
