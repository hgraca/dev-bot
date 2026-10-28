---
date: 2026-10-28
keywords: ["github", "gh-api", "http-404", "jq", "error-handling"]
aliases: ["gh api prints error body on stdout", "404 body not empty", "gh api silent failure"]
trigger-on: ["gh-api-response-validation"]
---

## `gh api` writes the error body to stdout too, so a non-empty capture is not success

`gh api` on a 4xx prints the JSON error body (`{"message":"Branch not found","status":"404"}`) to **stdout** as well as the human message to stderr, and exits non-zero. A helper that captures output and only checks for emptiness therefore treats "404" as a successful response. This bit a branch-protection reader: `classic_json="$(gh api ".../branches/main/protection" 2>/dev/null || true)"` yields a non-empty `classic_json` for a repository with no protection at all, so the caller believed protection existed and planned to delete it. Two rules follow: test the **exit status**, not the string (`if gh api ... >/dev/null 2>&1; then ...`), and when a body is captured with `|| true`, validate its shape before use — e.g. `jq -e 'has("enforce_admins")'` for a protection object — then clear it if the shape does not match. The same applies to any `gh api` call whose emptiness is used as a signal.
