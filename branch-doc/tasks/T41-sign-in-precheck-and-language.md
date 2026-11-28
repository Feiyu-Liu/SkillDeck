# ExecPlan: T41 App sign-in: offline check first, and the page in the App's language

Fixes R-1, and the App half of R-2, from
`../reviews/2026-11-28-t35-t39-review.md`. Client and App. **Land T42 first**:
the deployed service rejects unknown query parameters, so `ui_locales` must not
be sent to a service without T42. Simplicity rules **and UI rules**: see
`../execplan-template.md`.

## Set by the planner

### Goal

- **Offline:** a person who clicks "Sign in" while SkillDeck Cloud cannot be
  reached sees "Couldn't reach SkillDeck Cloud…" in Settings at once. No
  sign-in window opens.
- **Language:** a person using the App in Chinese gets the sign-in page in
  Chinese.

### Context

- **Read first:**
  - T36 and T37 as delivered;
  - `../cloud-api-contract-v0.md`: "App sign-in", including the new
    `ui_locales` parameter, and "Session";
  - `../reviews/2026-11-28-t35-t39-review.md`, R-1 and R-2.
- **Today:** with no connection, the system window opens and shows Safari's
  error page. Closing it returns to signed out with no message.

### Contract

- **Reachability check, in `CloudSignIn.signInWithBrowser`, before the
  authenticator is called.**
  - Send one `GET /api/auth/get-session` with no `Authorization` header, with
    a 10-second timeout.
  - Map the result:

    | Result | Outcome |
    | --- | --- |
    | Any HTTP response from 200 to 499, except 429 | reachable; continue |
    | 429 or 5xx | `CloudSignInFailed(server)`; the window does not open |
    | Connection failure or timeout | `CloudSignInFailed(network)`; the window does not open |

  - The response body is not read or used.
- **`signInWithBrowser` gains `String? uiLocale`.**
  - Send it as `ui_locales` only when it is `en` or `zh`.
  - The App passes `zh` when the App's current locale is Chinese, else `en`.
- **No new App state or text.** The existing T37 states and strings cover
  every outcome: "failed: network" and "failed: busy".

### Acceptance

- **Package tests,** with the fake service:
  - each row of the table, and that the authenticator is not called for the
    failure rows;
  - the timeout case, with a fake clock or client;
  - `ui_locales=zh` and `ui_locales=en` appear in the sign-in URL;
  - `null` or any other value sends no `ui_locales`;
  - the no-leak test still passes.
- **App widget tests:**
  - offline before sign-in shows the network text, with "Sign in" enabled
    again;
  - the App's locale reaches `signInWithBrowser`.
- **Native, against staging after T42 is deployed:**
  - with the App in Chinese, the page is Chinese;
  - with an unreachable origin (as in T37's validation), Settings shows the
    network text, and no window opens.
- **Screenshots** (UI rule 8), in `branch-doc/screenshots/T41/`:
  - the network-failure row after an offline click, in EN and ZH, light and
    dark;
  - the Chinese sign-in page in the system window.
- **Gates:** the `skills_cloud` gates and the App gates from `CLAUDE.md`, each
  with its own exit code.

### Scope fence

- **In scope:**
  - `packages/skills_cloud/lib/src/sign_in/` and its tests and fake;
  - the App's sign-in ViewModel and its tests;
  - this card's screenshots.
- **Out of scope:**
  - any new UI text or state;
  - the service (T42);
  - Device Authorization.
- **Expected size:** about 4–6 files, 150–300 lines with tests.

### Stop and ask if

- `get-session` without a token does not answer 200 on staging.
- The App's locale is not available where the ViewModel starts sign-in.

## Maintained by Codex

### Progress

- Implemented and validated on 2026-11-28; see the combined report below.

### Decision Log

- T42 was deployed before adding the App's `ui_locales` parameter. Anonymous
  staging `get-session` returned 200.
- Settings supplies the resolved locale directly to its ViewModel; no global
  locale state or configuration flag is added.
- Precheck uses `Client.send` with redirects disabled, cancels the stream
  without reading body bytes, and bounds the wait for response headers to 10 seconds. Cancellation errors
  are suppressed because an HTTP response already established reachability.
- Fake-clock coverage checks the deadline and late-response cancellation;
  native unreachable-origin acceptance uses the existing local-service fixture.

### Surprises

### Follow-ups

### Outcome

Implemented. See `../validation/t41-t44-2026-11-28.md` for per-command gates,
native and staging acceptance, screenshot paths, approved deviations and limits.
