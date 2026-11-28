# ExecPlan: <Txx> <title>

> Template. Copy to `branch-doc/tasks/Txx-<slug>.md`. The planner fills the
> first part; Codex keeps the last part current while it works. Say what and
> why, not how: anything this plan does not pin down is Codex's call, within
> the simplicity rules.

## Set by the planner

### Goal

One or two sentences: the behavior that is observable once this task is done.

### Context

Only what the repository cannot tell Codex: the decision this task implements,
summarized (not ADR text), and which `CONTEXT.md` files and existing code to
read first.

### Contract

The public surface this task adds or changes: signatures and typed outcomes
only. Anything not listed here is internal.

### Acceptance

- The behaviors that must hold, each backed by a test.
- Gates: the exact commands that must pass.

### Scope fence

- In scope: packages and directories.
- Out of scope: explicit non-goals, especially the adjacent work that is
  tempting to do now.
- Expected size: about N files, roughly M lines.

### Stop and ask if

Task-specific triggers. The simplicity rules below add the general ones.

## Simplicity rules (every task)

1. Build only what Acceptance needs. Add no hooks, options or extension points
   for later phases or for "flexibility".
2. Add no interface, abstract class, generic, factory or strategy unless this
   task has two concrete implementations, or a test fake needs the seam and the
   package already uses a port for that kind of dependency. A single
   implementation stays a concrete class.
3. Follow the nearest existing pattern in the package. If none fits, say so in
   the Decision Log before inventing one.
4. Stop and ask before adding a package dependency, a public export, a config
   flag or a schema migration that Contract does not list.
5. Do not refactor outside the scope fence, however improvable it looks. Note
   it under Follow-ups.
6. Prefer fewer files and layers. Do not split something into its own file or
   layer until two places use it.
7. If the diff grows past about twice the expected size, stop and report why
   before going on.
8. Tests prove Acceptance and the failure boundaries. Build no new test
   framework or helper unless at least two tests need it and `test/support/`
   has nothing that fits.
9. One card, one commit. Work outside the card, even if approved, goes in its
   own commit and is named in the Decision Log.

## UI rules (every task that changes what a person sees)

Added 2026-11-28. These rules come before visual or wording choices of your
own.

1. **Use only the card's strings.** Use the exact English and Chinese text the
   card gives. If a state has no text in the card, stop and ask; do not write
   one.
2. **Build from existing widgets.** Use the components already on the same
   screen, such as `SettingsGroup`, `SettingsRow`, `AppButton` with `loading`,
   and the theme's spacing and colors. No new colors, font sizes, icons,
   animations, dialogs, toasts, or custom painters, unless the card asks for
   them.
3. **Show what the person can do, not how it works.** No protocol names, codes,
   IDs, URLs, error codes, file paths, or technical causes in the UI.
4. **One primary action per state.** At most one secondary action. No button
   that does nothing useful in that state.
5. **Cancelling is not an error.** A person who cancels returns to where they
   started, with no message.
6. **No dead ends.** Every failure state shows one plain sentence and the
   action that recovers.
7. **Remove what the change replaces.** Delete the old widgets, strings in both
   ARB files, and their tests.
8. **Evidence:** attach screenshots of every state the card lists, in English
   and Chinese, in light and dark appearance, at the default window size, to
   the Outcome, under `branch-doc/screenshots/<card>/`. The reviewer accepts
   the UI from these. A golden or widget test alone is not enough.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

One line each, with the reason: every non-obvious choice, and every
abstraction, file split or deviation from the plan.

### Surprises

Anything in the repository that contradicted this plan.

### Follow-ups

Improvements noticed and deliberately left undone.

### Outcome

What shipped, the gates that ran and their results, and how the result
differs from the plan.
