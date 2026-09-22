---
date: 2026-09-22
keywords: ["devbot", "release", "semver", "version", "git-changelog"]
trigger-on: ["devbot-release-version-scheme"]
---

## `devbot:release` version scheme: a major of zero means four components

`release.sh` reads the major digit to decide a version's shape. A non-zero major is a stable release with three components (`X.Y.Z`, with `X.Y` normalising to `X.Y.0`); a major of zero marks the release as still unstable and carries four (`0.X.Y.Z`), whose last three components behave as major.minor.patch. The next minor therefore bumps the second component for a stable version (`1.2.3` → `1.3.0`, `1.4.0` → `1.5.0`) and the third for an unstable one (`0.1.2.3` → `0.1.3.0`, `0.7.4.0` → `0.7.5.0`). Other component counts are refused with `FATAL:` — `0.7.5` (three components, zero major) and `1.2.3.4` (four, non-zero major) both fail. The release-notes artifact follows the same components, one dash-separated component per version component: `release.v0-7-5-0.no-vcs.md` with heading `# Release v0.7.5.0`. Before this was supported, every four-part tag was filtered out of the remote tag list, so `version` reported `FATAL: no version tags on remote 'origin'` on any major-zero repo (dev-tools, dev-tools.ai, audit-log-client, laravel-prometheus).
