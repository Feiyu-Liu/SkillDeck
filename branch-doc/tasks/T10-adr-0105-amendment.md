# ExecPlan: T10 Append the 2026-11-23 revision to the private ADR-0105

Documentation only. No code. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

The private ADR-0105 records the accepted 2026-11-23 revision and the
maintainer's follow-up decisions of 2026-11-24, so the ADR on its own is
current.

### Context

- The private `docs/` directory is not part of this repository. Work in the
  maintainer's private docs checkout, wherever ADR-0105 lives there. Do not
  copy private ADR text into this repository.
- Source text: the "Decision" section, R1–R17, of
  `../0105-revision-2026-11-23-proposal.md`.
- Follow-up decisions of 2026-11-24, to add under R16 and R14 as dated notes:
  - Production service origin `cloud.skilldeck.cc`, staging
    `cloud-staging.skilldeck.cc`. One origin serves the Cloud API, Better Auth,
    and the `/device` approval page.
  - The email OTP provider is Resend.
  - A GitHub organization owns the GitHub OAuth Apps, one per environment.
  - The private service repository and the Cloudflare dev and staging account
    exist.

### Contract

- Append a section `## Amendments (2026-11-23)` to ADR-0105, holding the
  proposal's Decision section verbatim.
- Keep the R numbers, and keep the dated user-decision markers.
- Add the 2026-11-24 notes as a short dated list at the end of that section.
- Change no earlier text of ADR-0105. Where the revision supersedes an earlier
  decision, the R section already says so.

### Acceptance

- ADR-0105 contains the new section, and its R1–R17 text matches the proposal.
- A diff of the private docs shows only the appended section.
- In this repository, `branch-doc/0105-revision-2026-11-23-proposal.md`'s status
  line is changed from "ADR-0105 amendment pending" to "ADR-0105 amendment
  applied", and `branch-doc/README.md` is updated to match.

### Scope fence

- **In scope:** the private ADR-0105, and the two status lines in `branch-doc/`.
- **Out of scope:** rewording the decisions, and editing other ADRs.

### Stop and ask if

- ADR-0105 already has an Amendments section for 2026-11-23 that differs from
  the proposal.
- The private docs have no ADR-0105, or it is clearly a different document.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
