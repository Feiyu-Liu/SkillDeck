# ExecPlan: T39 Screenshot audit of the Cloud UI

Review input only: **no change to the App's behaviour or look.** The
maintainer and Claude review the screenshots and then write rework cards with
fixed states and text, as T37 does. Simplicity rules and UI rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

One document shows every state of every Cloud screen as a person sees it,
with its text and actions. Each item that breaks a UI rule is flagged, and
nothing is fixed.

### Context

- **Read first:**
  - the UI rules in `../execplan-template.md`;
  - `skilldeck-app/lib/features/cloud/presentation/`;
  - the Skill row and detail views that show Sync Status;
  - T31, T32, and T34's UI parts, and their tests, which already build most
    states with fakes.
- **Sign-in is excluded.** T37 replaces it. Include the signed-in, offline,
  and sign-out states, which T37 keeps.

### Contract

- **What to capture:** every state of each item below, in English and
  Chinese, light and dark, at the default window size, with the App's real
  fonts:
  - **Settings, Cloud section:** signed in; offline; signing out; sign-out
    failed; the metadata-unavailable note; Device Exclusions, empty and with
    two rows.
  - **Skill row:** each Sync Status mark: Device Only, Synced, Waiting to
    Upload, Applying, and Needs Attention.
  - **Skill detail:** the "Sync to Cloud" toggle, on and off, and the status
    with each Attention Reason.
  - **Attention actions:** for each Attention Reason, its actions, and each
    confirmation dialog.
  - **Incoming change review:** the diff of an incoming pack.
  - **Sync Merge conflict review:** choosing a side, and after choosing.
  - **Note Conflict review:** two texts, three texts, combining, and each
    error message it can show.
  - **New-Device step:** the sheet with three Skills, choosing some, and
    after activating.
  - **Account notices:** sync stopped after an error, storage limit reached,
    and any other notice the code can show.
  - **Any other Cloud state** found in the code. List it with the item it
    belongs to.
- **How:**
  - Build each state with the existing fakes: `FakeCloudService`, the fake
    Workspace repository, and the in-memory session store.
  - Capture on macOS with the real App shell, for example with an integration
    test that renders each state and saves a PNG.
  - Put the capture code under `integration_test/` or `tool/`, never in
    `lib/`, and record the command.
  - Widget-test images with the test font are not acceptable.
- **Output:**
  - **Files:** PNGs in `branch-doc/screenshots/T39/<item>/`, named
    `<state>-<en|zh>-<light|dark>.png`.
  - **Inventory:** `branch-doc/reviews/2026-11-28-cloud-ui-inventory.md`, with
    one row per state:

    | Item | State | When a person sees it | Text shown (EN / ZH) | Actions | Screenshot | UI rule notes |
    | --- | --- | --- | --- | --- | --- | --- |

    - **"UI rule notes"** names each rule the state breaks, by number, with one
      line of fact. Examples: a technical word shown; two primary buttons; a
      cancel that shows an error; a state with no way out; Chinese text that
      is a word-for-word rendering of the English.
    - Write no fixes and no proposals.
  - **Summary:** at the top, the number of states, and the count of notes per
    rule.

### Acceptance

- Every state above has all four screenshots, or a row saying why it cannot
  be reached.
- The inventory's text column matches the ARB files.
- `git diff --stat` touches only `branch-doc/`, and `integration_test/` or
  `tool/`.
- The App gates from `CLAUDE.md` still pass, each with its own exit code.

### Scope fence

- **In scope:** capture code, screenshots, the inventory, and the README row.
- **Out of scope:** any change under `lib/`, ARB files, or tests other than
  the capture code; sign-in states; fixes of any kind.

### Stop and ask if

- A state cannot be built without changing `lib/`.
- There are more than about 150 states. Report the count by item first.

## Maintained by Codex

### Progress

- [x] Captured 62 Cloud states in English/Chinese and light/dark, with real native App fonts. Wrote the complete inventory and rule notes; made no UI fixes.

### Decision Log

- Use existing fake service, repository, session store and real App shell. Screenshots are native-rendered, not widget-test font goldens.

### Surprises

### Follow-ups

### Outcome

Delivered 248 PNGs and capture-inventory.json under ../screenshots/T39/, and ../reviews/2026-11-28-cloud-ui-inventory.md. The full native capture and focused new-Device recapture passed. All four variants exist for every listed state. Product behavior/look are unchanged by this card. Native AX stress-harness limitations are documented in ../validation/t35-t39-2026-11-28.md.

Changes are committed separately by task; no push or deployment is included.
