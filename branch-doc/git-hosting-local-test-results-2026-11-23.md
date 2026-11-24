# SkillDeck Cloud Phase 1 Git hosting test results

23 November 2026 · Apple Silicon macOS · Local smart HTTP

Both hosts accepted a single push containing 500 retention refs. A fresh client fetched the expected set of 500 commit IDs from each host. Standard Git also served a 40 MiB binary intact. The Cloudflare Artifacts simulator rejected the ref update containing that file.

## Method

A C client linked against SkillDeck’s vendored libgit2 1.9.7 pushed and fetched over loopback HTTP. The standard host ran Git 2.47.1 through `git-http-backend`. The Artifacts host ran the official simulator from Wrangler 4.163.0 and Miniflare 5.20261116.0-beta. Its local binding issued the credentials for the scope checks.

Each fixture had 500 commits in a linear history and one `refs/retain/<commit-id>` ref per commit. The client pushed all 500 refs in one request, fetched the retention namespace into an empty repository and compared the set of target commit IDs against the fixture. A subsequent commit added 41,943,040 random bytes as `data.bin` alongside `SKILL.md`. After a successful upload, the harness fetched that commit and compared the file bytes with the original payload.

## Observations

| Operation | Standard Git | Artifacts simulator |
|---|---|---|
| Push 500 retention refs | Accepted in 1.496 s | Accepted in 7.597 s |
| Fetch into an empty repository | 0.407 s. All 500 commit IDs matched. | 0.421 s. All 500 commit IDs matched. |
| Push commit containing the 40 MiB file | Accepted in 2.650 s | Rejected in 2.423 s with `pre-receive hook declined` |
| Retrieve the 40 MiB file | Fetched in 1.681 s. File matched byte for byte. | No accepted ref to fetch |
| Fetch using a write credential | Outside the standard-host fixture | Succeeded in 0.120 s against an already populated client |
| Push using a read credential | Outside the standard-host fixture | HTTP 403 in 0.008 s |

The large-file rejection is consistent with the published 32 MiB per-file limit. The hook returned a generic error, so the exact rule that fired remains unconfirmed. The read and write credential results agree with the documented scopes. [Artifacts limits](https://developers.cloudflare.com/artifacts/platform/limits/) · [Git token scopes](https://developers.cloudflare.com/artifacts/api/git-protocol/)

Each timing represents one local observation. The harness checked commit-ID set equality under the retention namespace. Windows, the packaged app’s HTTPS transport, deployed Artifacts, a production self-hosted authorization gateway, and backup and recovery remain unverified. [Hosting decision brief](git-hosting-comparison-2026-11-23.md)

## Captured client output

Each operation line records the host, operation, refspec count, client exit code and elapsed seconds. A fetch with one wildcard refspec can retrieve all 500 refs.

```text
standard push 500 0 1.496 
standard fetch 1 0 0.407 
standard 500 exact refs True
standard push 1 0 2.65 
standard fetch 1 0 1.681 
standard 40MiB bytes match True
sim push 500 0 7.597 
sim fetch 1 0 0.421 
sim 500 exact refs True
sim push 1 1 2.423 ref rejected: pre-receive hook declined
sim fetch 1 0 0.12 
sim push 1 1 0.008 libgit2 -1: unexpected http status code: 403
```
