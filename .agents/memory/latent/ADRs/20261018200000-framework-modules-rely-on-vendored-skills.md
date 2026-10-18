---
date: 2026-10-18
keywords: ["react", "svelte", "skills", "external-modules", "vendored-skills"]
aliases: ["framework module skills", "first-party framework conventions"]
---

## Framework modules keep their MCP servers but not their own skills

The `react` and `svelte` modules no longer ship first-party conventions skills: `devbot:react` (504 lines) and `devbot:svelte` (338 lines) were deleted, and the modules now contribute only their MCP servers (next-devtools; the svelte gateway), while the six vendored skills declared in each `external-modules.json` are the sole convention source. Rationale: the first-party files duplicated roughly 70% of the vendored skills they themselves told the agent to load, and their unique halves (Next.js App Router scaffolding, ports/adapters modules, SMUI-only styling) described architecture no workspace project uses — the only live React project is Vite + React 19 + Tailwind/shadcn + atomic design, and no project uses Svelte at all. Their generic content also carried defects (two non-existent skill names in the React skill's load list, an SSR-unsafe `localStorage` example and a Svelte 4 store idiom in the Svelte skill), so the duplication was actively harmful. The framework-neutral structure guidance lives in the `frontend` module (`atomic-design`, `storybook`). This reverses the earlier accepted trade-off of keeping `devbot:react`/`devbot:svelte` beside the vendored namespaced skills; both `docs.md` files now describe MCP plus vendored skills instead of a first-party skill.
