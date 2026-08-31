---
date: 2026-08-12
keywords: ['tailwindcss', 'cascade-layers', 'css', 'shadcn']
trigger-on: ['unlayered-css-overrides-tailwind-utilities', 'inline-style-to-tailwind-regression']
---

## Unlayered hand-rolled CSS overrides Tailwind's layered utilities

When a dashboard has hand-rolled CSS that is NOT wrapped in any `@layer`, those rules beat Tailwind v4's `@layer utilities` regardless of selector specificity, because unlayered styles outrank layered styles in the CSS cascade-layers spec. Concretely: converting an inline `style={{ padding: '14px 16px' }}` to `className="px-4 py-[14px]"` silently falls back to a global `tbody td { padding: 13px 16px }` rule, because the unlayered `tbody td` selector wins over the layered `.px-4` utility even though `.px-4` is more specific. Inline `style={{}}` (highest priority) masks this until you remove it. Fix: wrap the dashboard's custom CSS in `@layer components` (or delete the global element rules as pages migrate) so utilities can override them. Until then, expect 1–2px deltas on elements with global rules (`tbody td`, `button`, `input`, `select`) after migrating inline styles to Tailwind classes.
