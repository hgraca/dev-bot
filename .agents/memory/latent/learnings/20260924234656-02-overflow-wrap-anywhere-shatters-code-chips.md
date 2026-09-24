---
date: 2026-09-24
keywords: ["css", "overflow-wrap", "mobile", "tables", "code-chips"]
---

# `overflow-wrap: anywhere` shatters code chips mid-identifier

Reaching for `.prose table code { overflow-wrap: anywhere }` to stop a code token overflowing a narrow table cell does the opposite of what a reader wants: it permits a break *inside* the token, so `git-conventional-commits` renders as `git-convent` / `ional-commits` with the pill's background and border fragmenting across lines. On a 420px viewport it shattered every chip in a Type/Name/Purpose table, and the same happens in list items.

What works: keep the chip atomic with `white-space: nowrap` on `td code` **and** `li code`, and make the container scroll instead. Give the table a floor and scroll an ancestor — `.prose { overflow-x: auto }` with `.prose table { min-width: 40rem }` below the mobile breakpoint.

Two approaches that do **not** work: `display: block; overflow-x: auto` on the table itself (the table still sizes to its container, so nothing overflows and nothing scrolls) and adding `width: max-content` on top of that (measured no widening). The scroll container must be an ancestor of the table, not the table.
