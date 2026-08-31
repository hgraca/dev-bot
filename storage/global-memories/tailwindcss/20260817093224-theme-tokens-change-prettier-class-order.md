---
date: 2026-08-17
keywords: ["tailwind", "prettier", "class-ordering", "theme", "format"]
trigger-on: ["tailwind-class-order", "prettier-tailwind"]
---

## Adding `@theme` tokens to one CSS entry changes prettier's class ordering project-wide

`prettier-plugin-tailwindcss` sorts utility classes based on the set of custom color tokens it finds in the CSS. Adding extra `@theme` tokens (e.g. `--color-success`, `--color-strong`, soft variants) to `resources/css/app.css` — even tokens the auth SPA never uses — changed the sort order of classes like `text-strong`, `border-success` in **unrelated dashboard files** that share the same `.prettierrc`, so `format:check` suddenly failed on 41 files. Fix: keep the `@theme` block's token *names* identical to what already exists (base shadcn set) and change only the `:root`/`.dark` *values*. New color utilities needed by one SPA should be added to that SPA's own CSS, not to a shared/themed entry, or the ordering shift must be applied repo-wide with `prettier --write` in the same commit.
