---
date: 2026-10-13
keywords: ["shadcn", "tsconfig", "paths", "alias"]
aliases: ["components.json alias", "shadcn add wrote to a literal @ dir"]
trigger-on: ["shadcn-add", "tsconfig-paths"]
---

## shadcn CLI resolves import aliases from the root tsconfig.json, not the app one

`shadcn add` maps the `@/…` aliases from `components.json` to real filesystem paths by reading `tsconfig.json` at the project root. When that root file is a solution-style config (`"files": []` plus `references`, with the real `compilerOptions` living in `tsconfig.app.json`), it declares no `paths` — so the CLI cannot resolve the alias and silently falls back to treating it as a literal path. It then writes `@/components/ui/button.tsx` and `@/lib/utils.ts` into a directory literally named `@/`, and exits 0.

Fix: put the same `paths` in the **root** `tsconfig.json` as in the app config. `shadcn` only reads the root file, so aliases declared solely in `tsconfig.app.json` are invisible to it. TypeScript 6 resolves `paths` relative to the file that declares them, so `baseUrl` is not required (and is deprecated). Verify by looking at where the files actually landed — the CLI's exit code is 0 whether or not the alias resolved.
