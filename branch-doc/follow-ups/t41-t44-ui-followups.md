# Follow-up: small UI items deferred from the T41–T44 review

Status: deferred by the maintainer on 2026-11-28. Not part of T45 or T46.
Source: `../reviews/2026-11-28-t41-t44-review.md`.

- **F-12, service sign-in page:** white text on the `#ee5a24` primary button
  is about 3.8:1, below 4.5:1 for 15 px text. Option: darken the button, for
  example to `#c2410c` (about 5.2:1).
- **F-13, App sign-in:** during the precheck (up to 10 seconds) Settings shows
  "Continue in the sign-in window." although no window is open yet. Option:
  show "Sign in" loading, with no row text change, until the window opens.
- **F-8, note dialog:** at 800 × 600 only one version is visible before
  scrolling. If people find this hard, shrink the dialog header so two fit.
- **Notice spacing:** the stopped notice covers the sidebar's Settings item,
  and its "Try again" button has no space above it.
- **"Mac" in Cloud strings:** "Hidden from this Mac" / "已在这台 Mac 上隐藏" and
  the signed-out text still say "Mac". Change them when Windows Cloud is
  planned.
