---
date: 2026-11-03
keywords: ["github-actions", "runs-on", "self-hosted-runner", "ami", "custom-image"]
aliases: ["failed to resolve image spec", "image not found in default images or repo config", "transfers-image"]
trigger-on: ["runs-on-custom-image", "self-hosted-runner-image"]
---

## RunsOn custom image resolution fails intermittently: "not found in default images or repo config"

A job with `runs-on: runs-on=${{ github.run_id }}/runner=<size>/image=<name>` can die in
`Set up runner` with `Failed to launch runner: failed to resolve image spec: image <name> not found
in default images or repo config`, even though `.github/runs-on.yml` defines `<name>` correctly and
the label worked minutes earlier.

How to tell it is transient and not a deleted AMI: the step log shows `RUNS_ON_AMI_ID` set to the
**default** runs-on AMI (e.g. `ami-0e259f92bdda28d89`) — the instance booted, and the agent failed
to pick up repo config — and the same or another repo resolves its own custom image within the same
window. Observed 2026-11-03: GET-E/core failed at 13:09 while resolving fine at 08:57, and
GET-E/hotels-api failed 12:58 with its own image then succeeded at 13:04. No workflow change fixes
it; re-running the job does. Confirm against `gh run list --workflow <file>` before touching config,
and compare a sibling repo that uses a custom image — a genuine AMI deletion breaks every repo at
once and never recovers on retry.
