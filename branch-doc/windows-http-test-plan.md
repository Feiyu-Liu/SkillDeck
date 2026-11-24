# Windows HTTP qualification plan

**Date:** 2026-11-23 (draft, revised the same day)
**Decision it informs:** which client carries all SkillDeck Cloud traffic on
Windows. The maintainer decided on 2026-11-23 to choose only after real-world
testing.
**Results go to:** `docs/validation/windows-http-<date>.md`, in the existing
evidence style.

> **Status: paused (maintainer decision 2026-11-23).** macOS comes first, and
> Windows builds keep Cloud off until a client qualifies (ADR-0105 revision,
> R17). The first run (`windows-http-2026-11-23.md`) qualified nothing:
>
> - **B is rejected.** It buffers whole uploads (U1), can't cancel a streamed
>   download (H1), and reports false idle timeouts (U3).
> - **A** still leaves a stalled TLS handshake open (T2: 0 of 200 closed).
> - **C** showed prompt handle-close cancellation and fixed-buffer 50 MB
>   transfers in a Python spike over plain HTTP. No Dart adapter exists.
>
> **When this resumes:**
>
> - C is the primary candidate: our own `BaseClient` over system `winhttp.dll`,
>   with abortable requests, not a fork of `win_http`. G1 no longer applies.
> - A under rule 4 is the fallback.
> - Run C's TLS cases on E1 with the test root in the Windows store, because
>   WinHTTP can't use an isolated trust context.
> - Fix the memory sampling so U1 and U2 report peak memory per transfer.
> - Also cover T1, the upload stalls in U3, and the cases the first run left
>   open.

**Revision note:** this plan no longer tests WebSockets or Durable Objects,
because Phase 1 has no realtime channel. Devices run Feed Checks instead. It now
covers Revision Pack uploads and downloads, because libgit2 no longer carries
cloud traffic.

## 1. Scope

**In scope:** Dart-side HTTPS traffic from the App to the Cloud service on
Windows:

- API requests: Device Authorization polling, Feed Checks, Head Advance,
  metadata writes, and device management;
- Revision Pack transfers: streamed uploads and downloads of pack files.

**Out of scope:**

- **libgit2.** It no longer moves cloud data. Public Git Sources keep their own
  WinHTTP transport (`packages/skills_workspace/native/README.md`).
- **macOS.** It uses `cupertino_http` and needs no comparison.
- **Linux,** which is not an App release target.

**Architecture constraint:** `skills_cloud` stays pure Dart and talks only to
the `package:http` `Client` interface. The App injects a platform client.
Whichever candidate wins, this boundary doesn't change.

## 2. Candidates

| ID | HTTP | Notes |
| --- | --- | --- |
| **A** | `dart:io` `HttpClient` through `IOClient` | The baseline, with no new dependency. The prototype measured that a TCP connection stalled during the TLS handshake can outlive `HttpClient.close(force: true)` (`tool/qualify_tls_cleanup.dart`, which returns `knownSdkLimitation`). |
| **B** | `win_http` 0.2.3 (`package:http` `Client` over async WinHTTP) | GPL-3.0; whether "only" or "or later" is unknown. Single maintainer, first released 2026-04-07. About 1.8k lines, so vendoring is feasible. |
| **C** | Our own minimal WinHTTP FFI, or a vendored fork of `win_http` | Spiked **only** if A and B both fail a must-pass test, or if B's licence or maintenance is unacceptable. |

## 3. Requirements under test

These come from the `skills_cloud` CONTEXT and the prototype's transport
contract:

1. **Transport rules:**
   - HTTPS only, with certificate and hostname verification kept;
   - redirects never followed;
   - credentials only in headers, never in URLs.
2. **Bounds:**
   - API calls: one total deadline covering DNS, TCP, TLS, headers, and body;
   - pack transfers: an idle timeout plus a total cap, because a pack can be
     tens of MB;
   - cooperative cancellation;
   - bounded request and streamed response sizes.
3. **Streaming:** packs upload from a file and download to a file, without
   buffering the whole body in memory.
4. **Resource reclamation:** a timed-out or cancelled request releases its
   socket and handles promptly, including one stalled mid-TLS-handshake.
5. **Windows networking:**
   - the system proxy (manual, PAC/WPAD, bypass list);
   - trust roots from the Windows certificate store, including enterprise
     roots for TLS-inspecting networks.
6. **Network changes:** survives sleep, resume, interface changes, and VPN
   toggles. Failures are typed, and the next Feed Check after recovery
   succeeds.
7. **Long sessions:** no handle, socket, thread, or memory growth over many
   hours of Feed Checks every 2 minutes.
8. **No leakage:** no bearer token, URL userinfo, or raw platform message
   appears in error objects or logs.
9. **Packaging:** works from a signed release build on a clean machine
   without developer tools.

## 4. Environments

| Env | What | Used for |
| --- | --- | --- |
| E1 | Windows 11 24H2 x64 VM | Most tests; snapshot before every proxy or trust change |
| E2 | Windows 10 22H2 x64 VM | Must-pass subset (the App manifest supports Windows 10 and 11) |
| E3 | Physical Windows 11 laptop, Wi-Fi plus Ethernet | Sleep, resume, and interface changes (N1–N6). VMs don't reproduce these faithfully. |
| E4 | CI Windows x64 runner | Repeatable automated subset (H1–H6, T1–T5, U1–U3) |
| S1 | Local fault-injection server (Dart, on a second host or loopback) | Stalls, oversized bodies, redirects, bad certificates, slow and interrupted transfers |
| S2 | Staging Cloudflare Worker with R2 and D1 | Realistic TLS, HTTP/2, and pack transfers through the Worker |
| P1 | Squid (manual proxy), a PAC file, and an authenticating proxy (Negotiate/NTLM) | Proxy tests |
| P2 | mitmproxy with its root installed in the Windows store | TLS-inspection tests |
| I1 | `clumsy` (WinDivert) | Latency, loss, and blackholing |

Use staging accounts only. No production service, real user data, or real
credentials.

**Builds:**

- `flutter build windows --release`, installed with the release installer on
  a clean E1 snapshot;
- plus a CLI harness: `skilldeck-app/tool/qualify_windows_http.dart`, which
  runs each candidate behind the same interface and emits JSON per test.

## 5. Measurement

- **Per process:**
  - `Get-Process -Id <pid>` for Handles, Threads, and PrivateMemorySize64,
    sampled every 10 s;
  - `Get-NetTCPConnection -OwningProcess <pid>` for socket count and state.
- **Server side:** S1 logs the time from accept to the client's FIN or RST.
  This is the physical-reclamation signal.
- **Timing:** monotonic timestamps in the harness; report p50, p95, and max
  over repetitions.
- **Logs:** capture all App and harness logs and error `toString()`s for the
  redaction check (X1).

## 6. Test cases

Each case runs against A, B, and, if spiked, C. **M** marks a must-pass case.

### HTTP correctness and security

| ID | M | Test | Pass criteria |
| --- | --- | --- | --- |
| H1 | M | `package:http` `http_client_conformance_tests` | All applicable cases pass. Record skips with the reason. |
| H2 | M | TLS trust: valid certificate; self-signed; wrong hostname; expired; untrusted intermediate | Valid succeeds. Every other case fails closed with a typed certificate error and sends no request bytes. |
| H3 | M | Enterprise root in the Windows store (P2), then the same with the root removed | With the root: succeeds. Without it: a typed certificate error. Nothing disables verification. |
| H4 | | Certificate revocation endpoint unreachable (I1 blackholes OCSP/CRL hosts) | The request completes or fails within the deadline. Record the behavior; a hang beyond the deadline fails. |
| H5 | M | 301, 302, 307, and 308 responses, to the same host and to another host | None followed. A typed redirect error. The `Authorization` header is never sent to the redirect target. |
| H6 | M | Response larger than the limit; streamed body that exceeds the limit midway | Aborted at the limit without buffering the whole body. Typed size error. Socket released (as in T1 below). |
| H7 | | HTTP/2 and HTTP/1.1 against S2; connection reuse across 100 sequential requests | Both work. Reuse is observed through connection count. No head-of-line hang. |

### Revision Pack transfers

Use packs of 100 KB, 1 MB, 10 MB, and 50 MB.

| ID | M | Test | Pass criteria |
| --- | --- | --- | --- |
| U1 | M | Streamed upload from a file to S1 and S2 | Bytes received equal the file's SHA-256. Process memory rises by less than 2× the client's chunk size, not by the pack size. |
| U2 | M | Streamed download to a file from S1 and S2 | The file matches the server's SHA-256. Memory as in U1. |
| U3 | M | Upload and download where S1 stops sending mid-body, and where it throttles to 10 KB/s | The stall fails typed at the idle timeout. The throttled transfer completes if it stays under the total cap and fails typed if it exceeds it. The socket is released as in T1. A partial download never replaces the target file. |
| U4 | | Cancellation at random points during a 50 MB upload and download | A typed cancellation within 250 ms. Reclamation as in T1. No partial file left at the target path. |
| U5 | | Upload through the authenticating proxy (P1) and the TLS-inspecting proxy (P2) | Same outcome as the matching P or H case. The digest still matches. |

### Deadlines, cancellation, and reclamation (the reason this plan exists)

The S1 server provides each stall mode. Each case runs 200 times with a 2 s
deadline.

| ID | M | Stall point | Pass criteria |
| --- | --- | --- | --- |
| T1 | M | TCP accepted, no TLS bytes from the server, as in the prototype's `qualify_tls_cleanup.dart` | The call returns a typed timeout within the deadline plus 250 ms (p95). The server sees FIN or RST within 1 s (p95) and within 5 s (max). Handles and TCP connections return to baseline after the run. |
| T2 | M | ClientHello received, no ServerHello | Same as T1. |
| T3 | M | TLS done, response headers never sent | Same as T1. |
| T4 | M | Headers sent, body stalls after 1 KiB | Same as T1. |
| T5 | M | User cancellation at random points during T1–T4 | The call returns a typed cancellation within 250 ms. Reclamation as in T1. |
| T6 | | DNS blackholed (I1) | A typed timeout within the deadline. No orphaned resolver threads (thread count back to baseline). |

### Proxy

| ID | M | Test | Pass criteria |
| --- | --- | --- | --- |
| P-1 | M | Manual system proxy set in Windows Settings (Squid) | HTTPS goes through CONNECT, as the Squid access log shows. |
| P-2 | M | PAC file and WPAD auto-detect | Follows the PAC result, including `DIRECT` for bypassed hosts. |
| P-3 | | Authenticating proxy (Negotiate/NTLM) | Either succeeds with the machine's default credentials, or fails with a typed proxy-auth error. The bearer token is never sent to the proxy, as the proxy log shows. Record which outcome happened. |
| P-4 | | Proxy configured but down | A typed error within the deadline. No silent direct fallback unless the PAC says `DIRECT`. |

Candidate A is expected to fail P-1 and P-2 unless we add our own WinHTTP
proxy discovery (`WinHttpGetIEProxyConfigForCurrentUser` /
`WinHttpGetProxyForUrl`). Record the cost of that work as part of A's result.

### Network transitions (E3, physical machine)

Each case runs twice: once with a request in flight, and once idle between
Feed Checks.

| ID | M | Event | Pass criteria |
| --- | --- | --- | --- |
| N1 | M | Sleep 1 min, then resume | An in-flight request fails typed within the deadline after resume. A wake-triggered Feed Check succeeds within 30 s of the network being up. |
| N2 | M | Sleep 30 min, then resume | Same as N1. |
| N3 | M | Wi-Fi to Ethernet switch, and the reverse | Same as N1. No stuck connection bound to the old interface. |
| N4 | | VPN on, and VPN off | Same as N1. Traffic follows the new route. |
| N5 | | Airplane mode for 2 min | Typed offline errors. Backoff doesn't exceed the cap. The next Feed Check succeeds when connectivity returns. |
| N6 | | Captive portal, which intercepts with an invalid certificate | Typed certificate error. No request bytes sent. |

### Lifecycle, isolates, and load

| ID | M | Test | Pass criteria |
| --- | --- | --- | --- |
| L1 | M | App quit during an in-flight API request and a pack transfer | The process exits within 2 s, and `beforeClose` drains Cloud resources. No crash dialog. No partial pack left at a target path. |
| L2 | M | Client used from a background isolate, then the isolate is killed mid-request | No crash. Handles are released after the isolate exits. |
| L3 | | 10,000 sequential requests, then 50 concurrent requests for 10 min | No errors except injected ones. Handle and memory slope near zero. p95 latency recorded. |
| L4 | | Device Authorization polling: 15 min at a 5 s interval, with injected `slow_down` | Interval honored. Stable resources. |
| L5 | | 24-hour soak against S2: a Feed Check every 2 minutes, a 1 MB pack round trip every 30 minutes, and random server errors and `Retry-After` responses | The interval and backoff are honored. Handles, threads, and memory stay flat (slope near zero). No unexplained failures. |

### Packaging, redaction, and licence

| ID | M | Test | Pass criteria |
| --- | --- | --- | --- |
| K1 | M | Signed release build, installer, clean E1 and E2 snapshots without developer tools | Runs. No missing DLLs. Native Assets are bundled. No new SmartScreen or Defender prompt. Record the installer size difference. |
| K2 | M | Release build under the existing Windows CI release tier | Builds reproducibly with `--enforce-lockfile`. |
| X1 | M | Grep every captured log and error string from all runs for the bearer token, URL userinfo, and raw WinHTTP/Schannel text | Zero matches. Errors carry stable codes only. |
| G1 | M | Not a test: confirm `win_http`'s licence (GPL-3.0-only or GPL-3.0-or-later) and its effect on the combined App; review the maintainer's responsiveness on issues and PRs | Written conclusion in the evidence doc, applying the maintainer's licence policy (an open question in the ADR-0105 revision). |

## 7. Decision rules

1. **A passes every must-pass case:** choose A, with no new dependency. This is
   not expected, because of T1–T4 and P-1/P-2.
2. **Otherwise, B passes every must-pass case and G1 is acceptable:** adopt B.
   Pin it to an exact version, or vendor it at a reviewed commit if the
   maintenance review in G1 is weak.
3. **Otherwise:** spike C. Its acceptance is this same plan.
4. **A candidate that fails only physical reclamation (T1–T5 server-side
   timing) but meets every deadline:** the maintainer may accept it as a
   documented known limitation, with the prototype's mitigation (a global cap
   on pending connection opens). This is a decision for the maintainer, not a
   pass.

Whatever is chosen is wired through the App's platform client injection, and
the CI subset (E4) becomes a regression gate for it.

## 8. Deliverables and rough effort

| Item | Estimate |
| --- | --- |
| S1 fault-injection server and the `qualify_windows_http.dart` harness, both candidates behind one interface | 2–3 days |
| Environment setup (E1–E3, P1–P2, I1, S2 staging) | 1–2 days |
| Automated runs (H, T, U, X1) on E1, E2, E4 | 1 day |
| Manual runs (P, N, K) | 1–2 days |
| Soak (L5) | 1 elapsed day, mostly unattended |
| Evidence doc and recommendation | 0.5 day |

The total is about 5–9 days. Removing WebSockets saved roughly a day of
testing, plus the WebSocket client itself.

## 9. Open items before starting

- **Staging endpoint (S2):** the staging environment is decided (ADR-0105
  revision, R16). It doesn't exist yet. Until it does, run everything against
  S1.
- **Windows on ARM64:** no current release target. Add it only if one appears.
- **Licensing:** whether GPL-3.0-only dependencies are acceptable at all is a
  policy question for the maintainer, independent of test results.
