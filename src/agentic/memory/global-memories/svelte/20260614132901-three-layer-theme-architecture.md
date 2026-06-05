---
date: 2026-06-14
keywords: ["svelte", "theme", "tokens", "architecture"]
---

## Three-layer theme architecture: primitives → themes → semantic tokens

Theme system uses three layers in src/style/: primitives.ts defines the global palette (colors, spacing, typography) as concrete values; themes/light-theme.ts and themes/dark-theme.ts map semantic token names to primitives for each mode; semantic-tokens.ts exports a Svelte writable store consumed by components. Components reference `$themeStore.color.primary`, not raw color values. This keeps palette changes isolated to primitives.ts and mapping changes isolated to theme files — components never change.
