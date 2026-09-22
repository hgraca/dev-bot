---
date: 2026-09-22
keywords: ["helm", "upgrade", "version-pinning", "drift"]
trigger-on: ["helm-upgrade-without-version", "helm-chart-version-pin"]
---

## A `helm upgrade` without `--version` installs latest and silently breaks a pinned chart version

If a repository pins a chart version in one install path (`helm upgrade --install app chart --version 0.121.0`) but another path calls `helm upgrade app chart` with no `--version`, the unpinned call installs whatever is newest. The running release then drifts arbitrarily far ahead of the pin — in the observability repo production ran chart 0.128.0 while `mk/common.mk` still declared 0.121.0 — and because the pinned path is wired into the normal lifecycle target, the next routine deploy silently *downgrades* the release. Anything derived from that version is then invalid: ClickHouse schema and migrations, and any reference snapshot captured from a fresh install at the assumed version, which is what made a TTL audit describe the wrong schema generation. Audit every `helm upgrade` for an explicit `--version`, and derive all of them from a single variable.
