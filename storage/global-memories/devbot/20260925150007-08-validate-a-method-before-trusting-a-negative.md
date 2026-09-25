---
date: 2026-09-25
keywords: ["devbot", "verification", "measurement", "grep", "analysis"]
trigger-on: ["absence-of-evidence", "tool-returned-empty", "interpreting-a-negative"]
---

## Validate a method against a known-good control before believing a negative

Three conclusions in one session were wrong because the _measurement_ failed, not the world. A registry `404` "proved" a container image tag did not exist — the same request returned 404 for a tag that was demonstrably running in production, because the registry redirects to an Artifact Registry backend that answers 404 without a token. An exact-string `grep` reported a rule absent from an agent file that in fact carried the rule in a deliberately _adapted_ wording. A section extractor mis-bounded a heading style and silently returned zero bullets from 11 of 12 files. Each produced a confident, quotable number — "no image exists", "6/12", "9/12" — that only collapsed when the probe was re-run against a case whose answer was already known, or the search was repeated for the _concept_ rather than the exact string. The rules that follow: before reporting an absence, run the same probe against something known to be present; treat a tool's empty or zero result as suspect rather than as data (a failed read that returned `0/17` for every node would have read as a wide-open cluster); keep "the request failed" distinct from "the thing is absent", and say which one was actually established; and prefer a conceptually-scoped search over an exact phrase, since an exact phrase is a hypothesis about the author's wording rather than evidence about the content.
