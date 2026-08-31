---
date: 2026-08-12
keywords: ['tailwindcss', 'shadcn', 'theme', 'card', 'border']
trigger-on: ['shadcn-missing-color-card-token', 'shadcn-missing-base-border-rule']
---

## shadcn Card renders transparent and borders use text color when @theme misses tokens and the base border rule is absent

Two silent styling failures happen when a CSS entry point is incomplete during a shadcn/Tailwind migration of a dashboard with hand-rolled CSS. (1) `Card` renders with a transparent background because `bg-card` resolves to an undefined `--color-card` — the `@theme` block must map every shadcn token, including the easy-to-forget `--color-card: var(--surface)`, `--color-card-foreground`, `--color-popover`, and `--color-popover-foreground`, not just primary/background/border. (2) Borders default to `currentColor` (the text color, e.g. `#344054`) instead of the light border color because the `@layer base { * { @apply border-border } }` rule is absent — this rule must exist in EVERY CSS entry point that renders shadcn components (a second SPA's `index.css`, not just the primary `app.css`). Symptom: white cards blend into the page, and borders show dark-gray instead of the light `#e4e7ec` border. A missing `--color-card` and a missing base border rule are both silent — the components render, just with the wrong background/border colors.
