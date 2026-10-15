---
date: 2026-10-13
keywords: ["shadcn", "cn", "clsx", "tailwind-merge"]
aliases: ["cn is not clsx plus tailwind-merge", "removing the cn dependency breaks shadcn"]
trigger-on: ["shadcn-add", "cn-util"]
---

## `cn` from a shadcn component is the official `cn` package, not a missing-alias artifact

Newer shadcn registry items import `import { cn } from "cn"` and declare `dependencies: ["cn"]` — `cn` is a real published package (`shadcn-ui/cn`), a compiled drop-in replacement for `clsx` + `tailwind-merge`. It looks exactly like the damage a broken path alias does, so it is easy to "fix" by deleting the dependency and rewriting the imports to `@/lib/utils` — which breaks the primitives.

Check the registry before touching it: `curl -s https://ui.shadcn.com/r/styles/<style>/button.json | jq '.dependencies'` lists the required packages, and the versioned source is in the registry's returned file content. The generated `lib/utils.ts` (`export { cn } from "cn"`) is likewise a re-export of that package, not a stub. Confirm the style in use from `components.json` (`style`, e.g. `radix-nova`).
