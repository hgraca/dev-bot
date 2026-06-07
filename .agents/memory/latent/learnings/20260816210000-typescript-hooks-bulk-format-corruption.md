---
date: 2026-08-16
keywords: ["devbot", "typescript", "format", "hooks", "indentation"]
---

# TypeScript hook files corrupted by a bulk format pass — no formatter guards `.ts`

A single batch operation mangled 11 files under `src/agentic/*/hooks/opencode/*.ts` — all sharing an identical `stat` mtime (single loop/script), all showing the same corruption: single-line bodies (`if (x) return`, one-line `catch`) exploded into blocks with the body at column 0/1 (indentation destroyed), trailing whitespace added, and `import type { Plugin }` reordered to after value imports. This pattern is the signature of an LLM-driven "format the code" pass, not a deterministic formatter.

Ruled out as cause: the project's `format-md`/`format-json`/`format-yml` hooks filter strictly by `.md`/`.json`/`.yml` — none touch `.ts`, and there is no `format-ts` hook. Prettier 3.9.4 never emits zero-indent bodies. No biome/oxc/eslint config exists in the repo.

Detection: `git status` flags the files; identical microsecond mtimes across them confirm one batch op. Recovery: `git checkout -- src/agentic/*/hooks/opencode/*.ts` (the changes were uncommitted corruption with no intent). Do not run a broad formatter over `.ts` until a TypeScript-aware format config/hook exists — nothing currently protects TypeScript files in this repo.
