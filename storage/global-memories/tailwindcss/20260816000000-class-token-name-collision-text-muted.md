---
date: 2026-08-16
keywords: ["tailwindcss", "token", "class-name", "collision"]
trigger-on: ["tailwind-token-class-name-collision"]
---

## Don't reuse a theme-token utility name for a hand-rolled component class

In Tailwind v4, every `--color-*` in `@theme` generates a matching utility (e.g. `--color-muted` → `text-muted`, `bg-muted`). If the old hand-rolled CSS also defines `.text-muted { color: var(--text-muted) }` inside `@layer components`, the Tailwind utility (in `@layer utilities`, which wins over `components`) overrides it — so `.text-muted` elements render with `--color-muted` instead of the intended muted gray. In the dashboard migration `--color-muted: var(--surface-2)` (≈white), so all legacy `.text-muted` text rendered near-invisible (`rgb(247,248,250)`), verified in-browser on `/app/invoices`. The correct token is `--color-muted-foreground`, so the fix is sweeping `text-muted` → `text-muted-foreground`. Rule: when migrating hand-rolled CSS alongside a `@theme` block, never keep a component class whose name collides with a theme-token utility — rename or delete it. `text-strong`/`text-success`/`text-danger` were safe here only because `@theme` defined those tokens to the same value the old class used.
