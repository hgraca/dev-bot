---
date: 2026-10-26
keywords: ["docker", "buildkit", "secret", "dockerfile", "image-config"]
aliases: ["--mount=type=secret", "required=true", "mode=0444", "build-arg leak"]
trigger-on: ["dockerfile-multi-stage", "dockerfile-build-secrets"]
---

## BuildKit secrets: the three things that make the migration work

A credential migrated from `ARG X` + `ENV X=$X` to `RUN --mount=type=secret,id=X` needs `mode=0444` when the step runs as a non-root UID (the default 0400 root-owned file is unreadable), and `required=true` when the build must not proceed without it — an optional mount only makes `cat` fail while the command continues with an empty value, which a cached install can satisfy. Two traps: (1) in `VAR="$(cat ...)" OTHER="${VAR}..." cmd` both assignments are expanded before any takes effect, so `OTHER` sees the empty/old value — `export VAR=...` in a prior command, or read the file twice; (2) only `ENV` is written into the image config (`docker inspect`), an `ARG` is not — so keeping an ARG as a compatibility fallback is defensible, keeping the ENV never is. `$$VAR` in a RUN reaches the shell as `$$` (the PID), not an escaped `$`; use a single `$` and let Docker substitute a declared ARG.
