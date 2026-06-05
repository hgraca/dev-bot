---
date: 2026-05-10
keywords: ["opencode", "session", "tool"]
---

## `git apply --3way` can mis-align hunks against unrelated call sites

While resolving conflicts in `patch-opencode.sh` for opencode PR `#14772` against `v1.14.46`, `git apply --3way` left conflict markers in `packages/opencode/src/session/prompt.ts` at L555–593. The "ours" side was a legitimate `sessions.updateMessage({ id, role, parentID, sessionID, mode, agent, variant, path, ... })` block. The "theirs" side was a totally unrelated hunk for a `streamText`/`handle.process({ system, messages, tools, model, toolChoice })` call shape — an old structure from when the PR was authored. Naively merging "theirs" produces a TypeScript error storm (parsed-as-block-statement instead of object literal). The PR's actual one-line intent was at a _different_ call site (the inline `[{ role: "assistant" as const, content: MAX_STEPS }]` array, which became `role: ProviderTransform.supportsAssistantPrefill(model) ? ("assistant" as const) : ("user" as const)`).
Fix: Treat `--3way` markers as **suggestions, not ground truth**. Always run `gh pr diff <num> --repo <owner>/<repo>` (or read the cached `.pr-N.patch`) to extract the PR's _actual_ intent before editing. If the marker is at an unrelated location, revert that block to the baseline (`git -C <src> show <target_ref>:<path>`) and apply the PR's intent at the correct site instead. Related work in [[patch-opencode]] / [[ADRs]].
