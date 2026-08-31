---
date: 2026-08-12
keywords: ['tailwindcss', 'css', 'shadcn', 'theme']
trigger-on: ['tailwind-theme-css-variables', 'shadcn-migration-handrolled-css']
---

## Map hand-rolled CSS variables to Tailwind tokens with @theme block for shadcn compatibility

When migrating a dashboard with hand-rolled CSS variables to shadcn/Tailwind, add a `@theme` block after `@import "tailwindcss"` that maps existing CSS variables to Tailwind's design tokens. This lets shadcn components work without changing the underlying color palette. Key mappings: `--color-primary: var(--primary)` (teal instead of Tailwind blue), `--color-background: var(--surface)`, `--color-border: var(--border)`, `--color-muted: var(--surface-2)`, `--color-muted-foreground: var(--text-muted)`, `--color-ring: var(--primary)`. Place the `@theme` block immediately after the Tailwind import in the dashboard's main CSS file.
