# ExecPlan: T37 App: sign in through the system sign-in window

After T36; it can be built against T36's fake before T35 is deployed. It
replaces the App's Device Authorization sign-in. The maintainer amended R14 on
2026-11-28. Simplicity rules **and UI rules**: see `../execplan-template.md`.
This card is mostly about experience: follow its states and text exactly.

## Set by the planner

### Goal

In Settings, a person clicks "Sign in", signs in in the system window that
opens, and is signed in when it closes. They never see or compare a code, and
never switch to a browser.

### Context

- **Read first:**
  - `../phase1-plan.md`, Sign-in (R14) as amended;
  - `../cloud-api-contract-v0.md`, "App sign-in";
  - T36's `CloudSignIn.signInWithBrowser` and `CloudWebAuthenticator`;
  - in the App:
    - `lib/features/cloud/presentation/widgets/cloud_sign_in_settings.dart`;
    - `lib/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart`;
    - `macos/Runner/MainFlutterWindow.swift`, which already hosts the
      `skilldeck/cloud_lifecycle` and `skilldeck/window_attention` channels.
- **Minimum macOS is 12.0.** `ASWebAuthenticationSession` with a custom
  callback scheme works there. Do not use the `https` callback form; it needs
  macOS 14.4.

### Contract

**Native side**, in `MainFlutterWindow.swift`, next to the existing channels:

- A channel `skilldeck/web_auth` with one method, `authenticate`. Its
  arguments are `url` and `callbackScheme`.
- It starts an `ASWebAuthenticationSession`:
  - `prefersEphemeralWebBrowserSession = true`, so no web session or cookie
    outlives the window;
  - its presentation anchor is this window;
  - it keeps a strong reference while the session runs.
- **Results:**
  - success returns the callback URL as a string;
  - `ASWebAuthenticationSessionError.canceledLogin` returns `nil`;
  - any other error returns a `FlutterError` with code `unavailable`, and no
    message from the system;
  - a second call while one runs returns `FlutterError` `busy`.
- No `Info.plist` URL scheme entry and no new entitlement. If either turns out
  to be needed, stop and ask.

**Dart side:**

- **`MacosWebAuthenticator`** in `lib/features/cloud/data/` implements
  `CloudWebAuthenticator` over the channel. `unavailable` and `busy` map to
  `CloudSignInFailed` with an unknown cause.
- **The ViewModel** calls `signInWithBrowser`. Its sign-in phases become
  `signedOut`, `signingIn`, and `failed` with a cause of `network`, `busy`, or
  `other`:
  - **remove** `starting`, `waiting`, `denied`, `expired`, the user code, the
    browser-open flag, and the pending Device Authorization;
  - **keep** every other phase (`sessionCheckFailed`, `offline`, `signedIn`,
    `signingOut`, `signOutFailed`) as it is.
- **Mapping results to states:**

  | Result | State |
  | --- | --- |
  | `CloudSignInSucceeded` | signed in, as today |
  | `CloudSignInCancelled` | signed out, **no message** |
  | `CloudSignInDenied` (the person chose Cancel on the page) | signed out, **no message** |
  | `CloudSignInFailed(network)` | failed: network |
  | `CloudSignInFailed(server)` | failed: busy |
  | anything else | failed: other |

**What the Settings row shows.** Use the existing `SettingsGroup`, one
`SettingsRow`, and `AppButton` as the file does today. Change only the states
below. Every text is exact. No other text, icon, dialog, toast, link, spinner
outside the button, or code appears.

| State | Row title | Row description | Trailing |
| --- | --- | --- | --- |
| signed out | `cloudAccount` (unchanged) | EN: "Sign in to sync your Skills between your Macs." ZH: "登录后，可在你的多台 Mac 之间同步 Skill。" | primary `AppButton` "Sign in" / "登录" |
| signing in (the system window is open, or the code is being exchanged) | `cloudAccount` | EN: "Continue in the sign-in window." ZH: "请在登录窗口中继续。" | the same primary button with `loading: true`. No Cancel button: the system window has its own |
| failed: network | `cloudAccount` | EN: "Couldn't reach SkillDeck Cloud. Check your connection and try again." ZH: "无法连接 SkillDeck Cloud，请检查网络后重试。" | primary "Sign in" / "登录" |
| failed: busy | `cloudAccount` | EN: "SkillDeck Cloud is busy right now. Try again in a minute." ZH: "SkillDeck Cloud 暂时繁忙，请稍后重试。" | primary "Sign in" / "登录" |
| failed: other | `cloudAccount` | EN: "Sign-in didn't finish. Try again." ZH: "登录没有完成，请重试。" | primary "Sign in" / "登录" |

- Replace the signed-out description string (`cloudSignedOut`) with the text
  above in both ARB files. Add three new keys for the failure texts and one for
  the signing-in text.
- **Delete** these keys from both ARB files, and the code that used them:
  `cloudRequestingCode`, `cloudVerificationCode`, `cloudVerifyInBrowser`,
  `cloudOpenBrowser`, `cloudBrowserOpenFailed`, `cloudSignInDenied`,
  `cloudSignInExpired`, `cloudSignInFailed`. Regenerate the localizations.
- **Behaviour:**
  - clicking "Sign in" while signing in does nothing (the button is loading);
  - leaving Settings while signing in does not cancel the attempt; returning
    shows the current state;
  - a success needs no extra message: the row turns into the signed-in row
    that exists today;
  - a failure message clears when "Sign in" is clicked again.
- **Remove** any Device Authorization use from the App, and the browser-launch
  helper if nothing else uses it. Do not touch `skills_cloud`'s Device
  Authorization code.

### Acceptance

- **Widget tests,** with a fake `CloudWebAuthenticator` and the T36 fake
  service: each state in the table renders exactly its text and button, in
  English and Chinese; each result maps to its state; cancel and denied show
  no message; a double click starts one attempt.
- **A search** of `lib/` and both ARB files finds none of the deleted keys, no
  "verification code", and no "验证码".
- **Native:** a manual run on macOS 12 or later against T35 on `wrangler dev`
  or staging. Record which. Run:
  - success with email OTP;
  - Cancel in the system window;
  - Cancel on the page;
  - airplane mode before clicking "Sign in".

  If neither service is available, say so and run only the cancel case.
- **Screenshots** (UI rule 8), in `branch-doc/screenshots/T37/`, each in
  English and Chinese, light and dark:
  - signed out;
  - signing in, with the system window open over the App;
  - each failure state;
  - signed in.

  Also write down whether macOS showed a system prompt before the window
  opened, and screenshot it if it did.
- **Gates:** the App gates from `CLAUDE.md`, each with its own exit code, and
  the macOS desktop E2E suite.

### Scope fence

- **In scope:**
  - the cloud sign-in ViewModel, widget, and providers;
  - `MacosWebAuthenticator`;
  - `MainFlutterWindow.swift`;
  - both ARB files and the generated localizations;
  - their tests.
- **Out of scope:**
  - the signed-in, offline, and sign-out states' text and layout;
  - Device Exclusions;
  - the service page's look (T35);
  - `skills_cloud`;
  - Windows and Linux.

### Stop and ask if

- A state appears that the table does not cover.
- `ASWebAuthenticationSession` needs an `Info.plist` entry or an entitlement.
- macOS shows a system prompt before the window, on every sign-in. Report it
  with a screenshot; the maintainer decides whether to keep the ephemeral
  session.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
