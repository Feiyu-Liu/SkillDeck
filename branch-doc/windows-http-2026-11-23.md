# Windows HTTPS qualification for SkillDeck Cloud

**23 November 2026 · Revised Phase 1 plan · Partial qualification**

No release client has qualified. A reproduced the TLS handshake socket leak. B consumed the entire upload before transmitting any pack data. Its source explicitly awaits `request.finalize().toBytes()` and allocates another native buffer for the body. Both results affect required cases. The rule for investigating C applies. The native C spike transferred a 50 MB pack in both directions with a fixed 64 KiB application buffer. A Dart adapter still needs qualification.

## Environment and scope

The Windows client and S1 ran on the same Dell Vostro 5890 desktop over loopback, Windows 11 x64 build 26200.9445, Dart 3.14.0, http 1.6.0 and win_http 0.2.3. Tests used synthetic pack bytes, test certificates and a synthetic bearer. The Windows root store and system proxy retained their prior configuration. A trusted only the fixture certificate or CA through an isolated SecurityContext. B used the default WinHTTP configuration. With the fixture root absent from Windows, B rejected the HTTPS fixture. Its positive pack measurements below use a separately labelled HTTP loopback diagnostic. The unavailable staging endpoint, clean VMs and laptop limit extrapolation to production. The revised run concerns API and pack HTTPS only.

## Revision Packs

Each upload paused the file source after 65,536 bytes. A separate connection checked whether S1 had already read 32,768 bytes, up to ten times at 100 ms intervals. S1 computed SHA-256 during receipt. The download wrote directly to a file and a separate process hashed that file. Sizes are decimal bytes.

| Client and path | 100 KB, 1 MB, 10 MB, 50 MB uploads | Same four downloads | S1 received bytes before upload source EOF |
|---|---|---|---|
| A, HTTPS | 4/4 hashes matched | 4/4 hashes matched | 4/4 |
| B, HTTP diagnostic | 4/4 hashes matched | 4/4 hashes matched | 0/4 |
| C, synchronous native WinHTTP via Python ctypes, HTTP diagnostic | 4/4 hashes matched | 4/4 hashes matched | Used repeated WinHttpWriteData and WinHttpReadData calls with a reusable 65,536-byte buffer |

At approximately ten-second spacing the Dart VM private-byte samples were 244,142,080 and 247,107,584 for A and 245,497,856 and 450,891,776 for B. These two samples span JIT startup and multiple operations. They cannot establish peak memory, per-transfer growth below two chunks, or a leak. The earlier launcher-only samples are excluded. U1 fails for B on the implementation and wire evidence. U1/U2 remain partially verified for A. The C probe demonstrates native file I/O only. It lacks the Dart Client interface, TLS positive control, async cancellation, resource recovery and App lifecycle coverage.

**U3 download.** S1 wrote 1 KiB then stalled, or wrote 1 KiB every 100 ms. The harness used a one-second idle deadline and preserved a pre-existing eight-byte target on timeout. A reported the stall after 1,032 ms, hit a two-second total cap after 2,004 ms, and completed the 100 KB slow download in 9,793 ms under a 20-second cap. B reported idle timeout in all three diagnostic cases (1,009–1,021 ms), including continuous progress at the server. The idle clock observes chunks delivered by the client API. This test does not identify the layer that delays delivery. Timing includes waiting for transfer cleanup. Upload stalls, peer teardown timing and randomized cancellation of 50 MB transfers remain open.

## HTTP and socket evidence

| Case | Revised Windows observation |
|---|---|
| H1 | Pinned upstream suite 0d813f9, 278 passed, 17 skipped, 14 failed across three configurations. A failed bodyless GET/HEAD chunked encoding. B failed six cases in each configuration, including streamed cancellation. Expanded log preserves capability skips and failures. |
| H2 | With an isolated trusted test root, A received HTTP 200 for the valid leaf and HandshakeException for self-signed, wrong name, expired and missing intermediate. S1 counted zero HTTP requests for each rejection. B returned ClientException for all five with the local root absent from Windows. This cannot distinguish the four failure causes for B. Cloud error mapping remains untested. |
| H5 | A over HTTPS and B over diagnostic HTTP returned the original status for each combination of 301/302/307/308 and 127.0.0.1/localhost. All target hit counters stayed zero. Stable Cloud error mapping and B over trusted HTTPS remain open. |
| H6 | With a 64 KiB bound the harness rejected a declared 50 MB body before writing bytes and stopped a chunked body at 65,536 written bytes. Original target preserved, peer closure observed within 4 ms of return in all four trials (A HTTPS, B diagnostic HTTP). Process peak and production error mapping remain open. |
| U4 download | Twelve early randomized cancellations per client during a throttled 50 MB download. Original files intact in 24/24. A maximum 4.46 ms to return and 0.50 ms from return to peer closure. B maximum 4.30 ms to return and 2.34 ms from return to peer closure. Same transport distinction as H6. |
| T2 | 200 trials per client. A deadline return p50/p95/max 2006/2014/2028 ms, peer closed within 5 s in 0/200. B deadline 2005/2015/2024 ms, peer closed in 200/200, closure after return 3/8/10 ms. |
| T3/T4 | A, 200 trials each. Deadline return p50/p95/max 2008/2019/2028 and 2007/2016/2017 ms. Peer closure after return 3/5/11 and 3/5/9 ms. |
| T5 subset | A, 200 randomised-timing cancellations per post-TLS stall. Cancellation p50/p95/max 1/1/7 and 0/1/4 ms. Peer closure 0/1/2 ms for both. Pre-handshake cancellation and B remain open. |

T2 peers read the ClientHello. Distinct T1 accept-without-reading and whole-process baseline recovery remain open. Peer EOF or socket error establishes peer-visible closure, without distinguishing FIN from RST. The harness issued deadlines. These return times do not validate stable Cloud error objects.

## Remaining gates and decision

- H3/H4, H7, U5, P-1 through P-4 and T6 require the proxy, trust, revocation, DNS or staging setups described in the plan. H6 process peak and production mapping, U3/U4 uploads, the remaining T cases, L1–L4 and full X1 still need executable coverage. Captured revised results contained no synthetic bearer sentinel. Full error strings, URL userinfo and application logs remain unqualified.
- N1–N6 require the designated laptop and controllable network. The SSH host had Ethernet connected and WLAN disconnected. The Windows 10 and clean Windows 11 VM, signed installer K1, reproducible CI build K2, E4 regression gate and L5 24-hour S2 soak are outstanding.
- G1 carries forward the previous package review below. The GPL variant and commercial distribution policy are unresolved. Vendoring B alone retains its licence obligations and buffered upload implementation.
- The plan allows a maintainer exception for a candidate failing only physical reclamation. A also failed H1 and has outstanding must-pass gates. There is no basis yet to exercise that exception or wire a client into the shipping App.

## Reproduction and evidence

The new entry point is `skilldeck-app/tool/qualify_windows_http.dart`. Its standalone dependency lock is in the sibling `windows_http_probe` directory. Use Dart 3.14.0, Python 3.11+ and an empty scratch directory on Windows. Resolve the probe package with `dart pub get --enforce-lockfile`, copy s1.py into scratch, and supply cert.pem/key.pem valid for 127.0.0.1 (make_certs.py generates valid.crt/valid.key, with fixture-root.crt as the trust anchor for the certificate matrix). The original pack run trusted a self-signed fixture leaf. For reproduction with generated certs, concatenate valid.crt and fixture-root.crt into cert.pem and use valid.key as key.pem. From scratch run the entry point with A, B or B --loopback-http. Run cert_cases.dart with the generated certs directory and the probe package configuration. native_pack_spike.py uses the same scratch-directory S1 fixture. The throwaway pack files total about 61 MB.

Raw revised results are in `.private/scratch/<private service repository>/windows-http-20261123/revised-*`. The expanded H1 output gives individual skips. Prior evidence follows as a dated appendix. Its WebSocket results belong to the superseded plan.

---

## Historical appendix · earlier HTTP and WebSocket plan

**Decision, 23 November 2026.** Both proposed clients missed a required case on Windows. A request deadline alone left a stalled Dart TLS connection open. The WinHTTP package closed that connection promptly, but failed to interrupt a streamed download in the upstream conformance suite. Native WinHTTP warrants further testing for WebSocket establishment. This run does not qualify an implementation for release.

## Test host and method

Windows 11 x64 build 26200.9445, accessed over SSH. The services and clients ran on Windows loopback. The host had developer tools and differed from the specified clean Windows 11 24H2 and Windows 10 environments. We ran the handshake comparison with Dart 3.13.4 and 3.14.0, http 1.6.0 and win_http 0.2.3. All traffic used synthetic fixtures. Tests that needed a trusted certificate supplied one to an isolated Dart SecurityContext. The Windows trust store and proxy settings stayed at their original values.

Each handshake trial opened its own listener. The peer accepted TCP, read the client's TLS bytes and sent nothing. At two seconds the harness recorded its deadline, triggered abort and closed the client. The server observed EOF or a socket error for up to five more seconds before destroying its own socket. Each row covers 200 trials in batches of 20. The observation measures peer-visible closure. It cannot distinguish FIN from RST or establish process-wide handle recovery. Quantiles use nearest rank.

## TLS handshake stall on the target SDK

All 600 Dart trials returned the harness timeout. The physical criterion requires closure within one second at p95 and five seconds at maximum.

| Dart 3.14.0 on Windows | Deadline elapsed p50 / p95 / max (ms) | Peers closed within 5 s | Closure after deadline return p50 / p95 / max (ms) |
|---|---:|---:|---:|
| A · IOClient, abort then force-close | 2005 / 2011 / 2021 | 0/200 | All exceeded the observation window |
| B · win_http, abort then close | 2003 / 2013 / 2020 | 200/200 | 2 / 6 / 7 |
| Dart WebSocket.connect with a dedicated HttpClient, force-closed on timeout | 2006 / 2016 / 2037 | 0/200 | All exceeded the observation window |

Dart 3.13.4 gave the same closure counts. Deadline p95 was 2017, 2012 and 2016 ms for A, B and WebSocket respectively. B's closure p95 was 6 ms, maximum 7 ms. This fixture exercises the read-ClientHello variant T2 and the W2 stall. A separate accept-without-reading T1 fixture, stable Cloud error mapping and process resource baselines remain open.

A separate C spike used Python ctypes to call asynchronous WinHTTP with the WebSocket upgrade option. Closing the request, connection and session handles during TLS closed **200/200** peer connections, with closure p50/p95/max **1/4/7 ms**. This establishes the native cancellation mechanism only. A Dart adapter, successful native upgrade, message handling and operating that adapter across isolates still require qualification.

## Other measured behavior

| Case | Windows observation |
|---|---|
| T3 / T4, Dart HTTP 3.13.4 | 200/200 timed out after TLS while awaiting headers, and 200/200 after reading exactly 1 KiB. Deadline p95 was 2024 / 2016 ms. Peer closure p95 was 5 / 6 ms, maximum 16 / 11 ms. |
| T5, cancellation after TLS, Dart HTTP 3.13.4 | 200 trials per stall, with reproducibly varied cancellation times. All surfaced RequestAbortedException. Cancellation p95 was 1 ms in both cases. Maximum was 4 ms while awaiting headers and 7 ms while reading the body. Cancellation during connection establishment remains open. |
| H2 subset, both HTTP clients, 3.13.4 | Both rejected a self-signed loopback leaf. The HTTPS server received zero application requests. A exposed HandshakeException, B exposed ClientException. Stable certificate-error mapping, wrong name, expiry, incomplete trust chain and enterprise trust remain open. |
| H5 subset, both HTTP clients, 3.13.4 | With followRedirects disabled, each returned the original 301, 302, 307 and 308 for targets on the same port and another port. No redirect target received a request or synthetic bearer. This used plain HTTP on loopback. HTTPS, different hostnames and a typed Cloud redirect error remain open. |
| W1 / W3 subset, Dart 3.14.0 | A local WSS server verified a synthetic Authorization header and an empty query. The client received close codes 1000, 1001, 1011 and 1012. The Dart server fixture rejected sending 1012, so a separate TLS server emitted that close frame on the wire. The client received 1012. Staging auth, backoff and reconciliation counts remain open. |
| X1 subset | The synthetic bearer value was absent from captured result files. Full App logs, ticket and userinfo fixtures, and platform-error mapping remain open. |

## H1 · upstream client conformance

The upstream suite was pinned to dart-lang/http commit 0d813f9. IOClient used its upstream capability flags. B used the 0.2.3 package's own default and custom configuration tests. Skips reflect capabilities declared to the suite. Each test runner's expanded output records individual reasons.

The completed 3.14.0 run recorded 278 passes, 17 skips and 14 failures across the three configurations. A accounted for 98 passes, three skips and two failures.

- A failed two bodyless StreamedRequest tests (GET and HEAD). The suite expected no chunked encoding. It also skipped method-case preservation, NUL header handling and ambiguous GET-with-body semantics.
- B failed the same six cases in each configuration on Dart 3.13.4 and 3.14.0. Two stream-subscription cancellation cases timed out at 30 seconds. Abort during streaming received all 10,000 units rather than stopping early. The remaining failures involved the Content-Length of a HEAD response and two redirect-limit cases. Redirect following was enabled in those two cases. The disabled-redirect observation above is separate.
- B's capability flags account for skips involving request streaming, method case and folded headers. The suite also emitted skips for individual stream cases and GET-with-body semantics. Failed streaming cancellation matters for SkillDeck's bounded downloads even if the app only sends small requests.

## Licensing and maintainership

The 0.2.3 distribution contains the GPL v3 license text. GitHub identifies GPL-3.0. The reviewed package metadata did not establish an explicit only/or-later grant. SkillDeck CONTRIBUTING.md declares first-party code GPL-3.0-or-later and describes commercial licensing. A GPLv3 distribution may be feasible under the applicable distribution obligations. Vendoring the same code does not grant a separate commercial license. The GitHub API returned one contributor with seven contributions and an empty all-state issues/PR list, so response time cannot be assessed. G1 remains open for the maintainer. [Package](https://pub.dev/packages/win_http/versions/0.2.3) · [Repository](https://github.com/edde746/win_http)

## Remaining qualification

No candidate qualifies under the handoff's decision rules. Before building a full native adapter, rerun the failing cancellation cases against any proposed fix or replacement. Retaining Dart's stalled-open behavior under a global cap needs the explicit exception described in the plan.

Outstanding gates include H2–H7 coverage beyond the subsets above, T1/T5/T6 and native resource counters, P-1–P-4, W1/W3 application integration, W4–W6, N1–N6, L1–L5, K1/K2 and full X1. Proxy/trust mutation needs a disposable snapshot. Network transition tests need the specified physical laptop. Staging DO and clean installer runs need their respective environments. The 8-hour and 24-hour soaks, CI regression gate and release build were not run.

## Reproduction

Retained private fixtures and JSONL results are under `.private/scratch/<private service repository>/windows-http-20261123/`. The code is isolated from App dependencies. In that directory, resolve the pinned packages and run the following on Windows. Each measured row records the elapsed deadline and peer-observed closure. A null closure means observation expired.

```powershell
dart pub get
dart qualify_windows_http.dart A 200 20
dart qualify_windows_http.dart B 200 20
dart qualify_windows_http.dart WS 200 20
python native_upgrade_probe.py
```

For H1, place the upstream conformance package at `h1/conformance` from the pinned commit, then run `dart pub get` and `dart test -r expanded --concurrency=1` in `h1`. The probe scripts, package locks and raw measurements can be inspected independently of the application.
