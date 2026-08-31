---
date: 2026-08-12
keywords: ['css', 'tailwindcss', 'shadcn', 'dashboard']
trigger-on: ['shadcn-sheet-dialog-dashboard', 'tailwind-missing-dashboard']
---

## Shadcn components render invisible in DOM without Tailwind CSS import

When using shadcn/ui components (Sheet, Dialog, etc.) in a dashboard SPA that has hand-rolled CSS, the components render in the DOM but are visually invisible. Root cause: shadcn uses Tailwind utility classes (`fixed`, `z-50`, `bg-background`, `bg-black/80`) that have no effect unless `@import "tailwindcss"` is in the dashboard's CSS entry point. Additionally, `@import "tw-animate-css"` is required for slide-in/out animations (`data-[state=open]:animate-in`, `slide-in-from-right`). Both imports must be added to the dashboard's main CSS file (e.g., `resources/js/app/index.css`). The Inertia SPA has these imports already; the dashboard SPA does not.
