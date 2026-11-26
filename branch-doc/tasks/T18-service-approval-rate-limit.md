# ExecPlan: T18 Approval page rate limit and lockfile registry

Milestone M3 follow-up. **Runs in the private service repository.** Fixes
items T17-1 and T17-3 of `../reviews/2026-11-27-m3-review.md`. The maintainer
copies this card and the updated `../cloud-api-contract-v0.md` into that
repository; Codex keeps the maintained sections of that copy. Simplicity
rules: see `../execplan-template.md`.

## Set by the planner

### Goal

A person approving a valid code never sees "invalid or expired" because of
page loads, theirs or other people's behind the same address. When a real
limit is reached, the page says so honestly. The lockfile installs from the
public npm registry.

### Context

- **T17-1, reproduced on dev:**
  - Each signed-in load of `/device` calls the plugin's `GET /api/auth/device`
    to claim the code.
  - The plugin limits that path to 5 requests per client IP within the code
    lifetime (10 minutes).
  - From the 5th load from one address, the plugin answers 429. The page then
    shows "This sign-in request is invalid or expired. Start again in
    SkillDeck."
  - Approving still works, because approval does not call the claim endpoint.
- **What the limit is for:** it slows guessing of user codes. Keep that
  protection. With 8 characters from a 32-character alphabet, a user code
  has about 40 bits, and a code lives 10 minutes.
- **Better Auth** lets a configuration override a path's limit through
  `rateLimit.customRules`. Check how 1.7.28 combines that with the plugin's
  own rule before relying on it.
- **Contract v0 now lists HTTP 429** `rate_limited` as "try again later"
  (Conventions, added by T19). The API answer stays as it is today.
- **T17-3:** all `resolved` URLs in `package-lock.json` point at a
  mainland-China npm mirror. From a cloud session outside China that host did
  not answer.

### Contract

- **No repeated claims:** a load of the approval page for a code that already
  belongs to the signed-in account does not call the claim endpoint again, and
  does not count toward its limit.
- **Limit:** keep a per-IP limit on claims, but raise it so that normal use
  behind one shared address is never refused. Choose the number and window,
  and record them, with the guessing cost they allow, in the Decision Log.
- **Page text:** when a claim is refused with 429, the page answers 429 and
  says there were too many attempts and to wait a minute. It no longer says
  the code is invalid or expired. Other failures keep today's text.
- **Lockfile:** regenerate `package-lock.json` against
  `https://registry.npmjs.org/`. Package versions and integrity hashes do not
  change.
- No change to the contract, the endpoints, or the plugin.

### Acceptance

Tests in the Workers runtime against a local D1, as in T17, unless noted.

- One signed-in person loads the approval page for one code 10 times in a
  row, and each load shows the review page.
- 10 accounts behind one `cf-connecting-ip` each open their own new code
  within 10 minutes, and each sees the review page.
- Past the new limit, the page answers 429 with the "too many attempts" text,
  and approving an already claimed code still works.
- Every `resolved` URL in the lockfile is on `registry.npmjs.org`.
  `npm ci --ignore-scripts` with no registry override and the full test suite
  pass.
- All T17 tests pass unchanged.
- **Gates:** the repository's format, typecheck, device tests, full tests, and
  staging build. Report each command's own exit code.

### Scope fence

- **Out of scope:**
  - T17-4 (the legacy Linux test failure) and T17-5 (the earlier design's
    code);
  - deploying;
  - any other contract or endpoint change.
- **Expected size:** about 3–6 files, 100–300 lines excluding the lockfile.

### Stop and ask if

- The fix needs a patch to `better-auth`, or a change to a public path.
- The limit that normal use needs makes guessing a live user code practical,
  in your estimate.
- Regenerating the lockfile changes any package version or integrity hash.

## Maintained by Codex

Kept in the service repository's copy of this card.
