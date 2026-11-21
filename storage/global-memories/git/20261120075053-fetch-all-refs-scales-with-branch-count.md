---
date: 2026-11-20
keywords: ["git", "fetch", "refspec", "shallow-clone", "watchdog"]
aliases: ["refs/heads glob fetch", "fetch all branches slow", "updater always fails on one repo"]
trigger-on: ["git-fetch-owned-clone", "external-module-update"]
---

## Fetching `+refs/heads/*` scales with the upstream's branch count, not with what you need

An updater that resets a managed checkout to `origin/<branch>` needs exactly one ref, but the obvious fetch refspec `git fetch --depth 1 <url> '+refs/heads/*:refs/remotes/origin/*'` transfers the tip of every branch — and, because tag auto-follow is on by default, every tag that points into the fetched set, too. On one upstream with 488 branches and 232 tags that fetch took 127s on a fast connection, so a 20s network watchdog killed it on every run: the symptom is an updater that warns "failed to update <repo>" for one module while all the others sync, with no error text because the caller discards stderr. The narrow form costs seconds: `git fetch --depth 1 --no-tags <url> '+refs/heads/<branch>:refs/remotes/origin/<branch>'`, which is also what `git clone --depth 1` already does (a shallow clone is single-branch by default, so the update was fetching far more than the clone ever had). Measure before blaming the network — time the fetch by hand against the watchdog cap.
