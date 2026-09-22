---
date: 2026-09-22
keywords: ["release", "git", "semver", "version", "git-changelog"]
see: ["ADRs/20260920132448-gated-release-command-script-owns-determinism.md"]
---

## Major-zero releases carry four version components

`release.sh` accepted only two- or three-component versions, so `devbot:release` refused every repo whose tags carry a leading `0.` — `get-e/dev-tools` (`0.7.4.0`), `audit-log-client` (`0.1.14.0`), `dev-tools.ai` (`0.4.6.0`) and `laravel-prometheus` (`0.1.0.0`) among them. `release.sh version` reported `FATAL: no version tags on remote 'origin'` there, because `_last_remote_tag`'s filter (`^[0-9]+\.[0-9]+(\.[0-9]+)?$`) discarded every four-part tag while the tags were present on the remote. The scheme now reads the major digit: a **non-zero major is a stable release with three components** (`X.Y.Z`, with `X.Y` normalising to `X.Y.0`), and **a major of zero marks the release as still unstable and carries four** (`0.X.Y.Z`), whose last three components behave as major.minor.patch.

The next minor therefore bumps the second component for a stable version (`1.2.3` → `1.3.0`, `1.4.0` → `1.5.0`) and the third for an unstable one (`0.1.2.3` → `0.1.3.0`, `0.7.4.0` → `0.7.5.0`). `_normalise_version` is the single source of the shape rule, and `_last_remote_tag` now validates each remote candidate through it instead of re-encoding the rule in its own grep, so the two cannot drift. Component counts are held strictly: a three-component version with a zero major (`0.7.5`), a four-component one with a non-zero major (`1.2.3.4`), and anything longer or non-numeric are all refused. The release-notes artifact follows the same components — `release.v0-7-5-0.no-vcs.md` with heading `# Release v0.7.5.0` — one dash-separated component per version component, extending the `v1-5-2` ↔ `# Release v1.5.2` pairing rather than truncating a trailing zero.

No repo in the org uses a three-component zero-major tag, so no existing release line changes behaviour; a hypothetical `0.5.0` would now be refused rather than bumped to `0.6.0`. Two deliberately unchanged behaviours remain: `merge`, `tag`, `push` and `release` still take the version from `version`/`--version` and never invent one, and tag names still carry no `v`.
