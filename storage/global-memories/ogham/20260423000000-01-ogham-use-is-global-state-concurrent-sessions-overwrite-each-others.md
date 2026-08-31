---
date: 2026-04-23
keywords: ["ogham"]
---

## `ogham use` is global state — concurrent sessions overwrite each other's profile

`ogham use <profile>` persists a global default profile. If session A sets `k8s-gete` and session B sets `devbot`, all subsequent `ogham store` calls in session A silently use the `devbot` profile. This was discovered when a k8s-gete wrap-up stored a checkpoint under the devbot profile.
Fix: Always pass `--profile <name>` explicitly on every `ogham store` and `ogham search` call. Profile is resolved from `project_name` in `devbot.ini` (fallback: project root dir basename). See the `ogham` skill, section 1 (Profile Resolution).
