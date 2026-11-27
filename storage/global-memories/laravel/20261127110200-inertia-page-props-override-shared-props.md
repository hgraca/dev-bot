---
date: 2026-11-27
keywords: ["inertia", "shared-props", "page-props", "laravel"]
aliases: ["shared prop override", "monogram prop null"]
trigger-on: ["inertia-shared-props", "inertia-page-props"]
---

## An Inertia page prop overrides a shared prop of the same name

`PropsResolver::resolve()` does `array_merge($this->resolveSharedProps($shared), $props)`, so page
props win. That is what lets a controller hand a screen a value the shared middleware deliberately
withheld from that context — e.g. a mark shared only to signed-in tenants, passed explicitly on a
guest page. Worth knowing before adding a second name (`monogram_override`) or unguarding the
shared prop: the collision is safe, and the page-level prop is the smaller blast radius.
