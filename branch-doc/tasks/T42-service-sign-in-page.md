# ExecPlan: T42 Service: a clear, two-language App sign-in page

Fixes R-2 from `../reviews/2026-11-28-t35-t39-review.md`. **Runs in the private
service repository.** Land and deploy it to staging before T41. Simplicity
rules **and UI rules**: see `../execplan-template.md`. This card is about what a
person sees: follow its states, text, and look exactly.

## Set by the planner

### Goal

The page in the App's sign-in window:

- speaks the App's language;
- follows the system's light or dark appearance;
- asks for the email once;
- has one obvious next step in every state.

### Context

- **Read first:**
  - `../cloud-api-contract-v0.md`, "App sign-in", including the new
    `ui_locales` parameter. Copy that change into the service repository's
    copy of the contract.
  - In the service: `src/auth/app-sign-in.ts` and `src/web/device.ts`
    (`devicePage` with `appSignIn: true`), and their tests.
- **Today's page:**
  - English only, light only, unstyled browser controls;
  - two separate forms that both ask for the email;
  - a plain-text "Invalid sign-in request." page.
- **This card changes only the `/app/sign-in` pages.** The `/device` page
  stays as it is.

### Contract

#### Language

- Store `ui_locales` (`en` or `zh`, else derived as the contract says) on the
  sign-in attempt, so every later step of the same attempt uses it.
  - This needs one migration, adding a column to `appSignInAttempt`.
- Set `<html lang>` to `en` or `zh-CN`.
- The invalid or expired page, which has no attempt, uses `Accept-Language`.

#### States and exact text

| State | Heading | Text | Field(s) | Primary | Secondary | Bottom link |
| --- | --- | --- | --- | --- | --- | --- |
| **Email** (first view) | EN "Sign in to SkillDeck" / ZH "登录 SkillDeck" | EN "Enter your email and we'll send you a 6-digit code." / ZH "输入邮箱，我们会给你发送 6 位验证码。" | "Email" / "邮箱", type email, autofocus | "Continue" / "继续" | Only when GitHub is enabled: a divider "or" / "或", then "Continue with GitHub" / "使用 GitHub 继续" | "Cancel" / "取消" |
| **Code** (after a code is sent) | same | EN "We sent a 6-digit code to {email}. It expires in 5 minutes." / ZH "我们已向 {email} 发送 6 位验证码，5 分钟内有效。" | "Verification code" / "验证码", one-time-code, autofocus | "Sign in" / "登录" | a text link "Back" / "返回", which shows the Email state with the email filled in | "Cancel" / "取消" |
| **Code, wrong or expired** | same | the Code text, then in the error colour: EN "That code is wrong or has expired. Try again, or go back to get a new code." / ZH "验证码不正确或已过期。请重试，或返回重新获取验证码。" | same, emptied | same | same | same |
| **Email, sending failed** (any failure of send, including rate limits) | same | the Email text, then in the error colour: EN "We couldn't send a code right now. Try again in a minute." / ZH "暂时无法发送验证码，请稍后再试。" | email kept | same | same | same |
| **GitHub did not finish** (the person returns from GitHub without signing in) | same | the Email text, then in the error colour: EN "GitHub sign-in didn't finish. Try again." / ZH "GitHub 登录没有完成，请重试。" | same | same | same | same |
| **Invalid or expired attempt** (wrong `client_id` or `redirect_uri`, no or expired attempt cookie) | EN "This sign-in has expired" / ZH "本次登录已失效" | EN "Close this window, then click Sign in in SkillDeck again." / ZH "请关闭此窗口，然后在 SkillDeck 中重新点击“登录”。" | none | none | none | none |

- **Signing in succeeds:** redirect at once, as today. No page is shown.
- **"Cancel"** redirects with `access_denied`, as today.
- **The page's `<title>`** is the state's heading.
- **No other text appears:** no user code, no device name, no technical
  message, no status code.
- **The email between steps** is carried in a hidden form field of the Code
  form.
  - It is never in a URL, never stored by this page, and never logged.
  - `{email}` is HTML-escaped.
- **The GitHub error return** must reach the "GitHub did not finish" state of
  the same attempt. Today it would reach the invalid page; fix the
  `errorCallbackURL` so it does.

#### Look

Write it as inline CSS in the page, with no external fonts or files.

- **Layout:**
  - one centred card, at most 400 px wide;
  - 28 px padding, 12 px corner radius, a 1 px border;
  - full-width fields and buttons, each 44 px high, with an 8 px radius;
  - 16 px between elements;
  - no horizontal scrolling at 320 px wide;
  - the Email state fits without scrolling in a 480 × 600 window.
- **Type:**
  - `system-ui, -apple-system, "PingFang SC", "Noto Sans SC", sans-serif`;
  - heading 22 px, weight 600;
  - text 15 px, line height 1.5;
  - labels 13 px, weight 500.
- **Colours,** switched with `prefers-color-scheme`:

  | Token | Light | Dark |
  | --- | --- | --- |
  | page background | `#f7f7f6` | `#161616` |
  | card background | `#ffffff` | `#1f1f1f` |
  | border | `#e4e4e2` | `#2e2e2e` |
  | text | `#1e1e1e` | `#f2f2f2` |
  | secondary text and links | `#5e5e5e` | `#a3a3a3` |
  | primary button | `#ee5a24`, white text | `#ee5a24`, white text |
  | secondary button | transparent, border colour border, text colour text | same |
  | error text | `#b42318` | `#f97066` |
  | field background | `#ffffff` | `#262626` |

- **Behaviour:**
  - focus outlines stay visible;
  - while a form submits, its primary button is disabled.

  No other JavaScript.

### Acceptance

- **Tests in workerd:**
  - every state in the table, in EN and ZH, renders exactly its text and
    controls, and nothing from the old page;
  - `ui_locales` wins over `Accept-Language`, and `Accept-Language` decides
    when it is absent or unknown;
  - the language holds across all steps of one attempt, including the GitHub
    return (with the existing test double);
  - the email never appears in a URL or a log.
- **Existing tests still pass:**
  - every T35 security test: PKCE, replay, concurrency, rate limit, origin
    check, and the cancel redirect;
  - the `/device` tests.
- **Screenshots in real Chromium,** in `branch-doc/screenshots/T42/`:
  - every state, EN and ZH, light and dark, at 480 × 600;
  - plus the Email state at 320 px wide.
- **Staging:**
  - deploy after the maintainer asks;
  - run the email flow once in EN and once in ZH by hand;
  - record the version.
- **Gates:** the service's typecheck, format, and full test suite, each with its
  own exit code.

### Scope fence

- **In scope:**
  - `/app/sign-in` page rendering and its handler;
  - one migration;
  - the contract copy;
  - tests;
  - screenshots.
- **Out of scope:**
  - the `/device` page;
  - the token endpoint;
  - any change to sign-in security;
  - the App (T41).
- **Expected size:** about 4–6 files, 300–600 lines with tests.

### Stop and ask if

- Better Auth's OTP send or sign-in errors cannot be told apart from other
  failures, so the table's states cannot be reached.
- The CSP blocks the inline style or the button-disable script.
- A state appears that the table does not cover.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
