---
date: 2026-08-16
keywords: ["react", "radix", "shadcn", "playwright", "e2e"]
trigger-on: ["radix-popover-testing", "shadcn-select-e2e"]
---

## Radix popover keeps the closing content mounted during exit animation; shadcn Select is not a native `<select>`

Three Radix testing traps surfaced while converting specs from hand-rolled CSS to shadcn components:

1. **Popover exit animation double-match.** Radix `Popover` keeps the closing `PopoverContent` in the DOM (with `data-state="closed"`) while it animates out, so immediately after opening a second popover there are briefly TWO `[data-testid="filter-menu"]`/`[data-slot=...]` elements — Playwright then throws a strict-mode violation ("resolved to 2 elements"). Fix: scope queries to the open one: `page.locator('[data-testid="filter-menu"][data-state="open"]')`. Plain `getByTestId('filter-menu')` is racy.
2. **shadcn `Select` is a button + listbox, not a native `<select>`.** Playwright's `selectOption()` and `toHaveValue()` only work on real `<select>`/`<input>` elements and fail on the Radix trigger button. Drive it by id + item: `await page.locator('#feedback-status').click(); await page.locator('[data-slot="select-item"]').filter({ hasText: 'Under review' }).click();` and assert the trigger text with `toHaveText(...)`.
3. **Dialog `aria-labelledby` is a dangling id.** Radix `Dialog.Content` injects `aria-labelledby` pointing at an id that does not exist (no `DialogTitle` rendered) even when `aria-label` is set. Chrome's a11y tree still resolves the `aria-label`, so `getByRole('dialog', { name: '...' })` works — but the attribute is misleading; prefer rendering a visually-hidden `DialogTitle` (`sr-only`) when you control the atom.
