---
name: devbot:atomic-design
description: "Use when structuring frontend components by atomic design — atoms, molecules, organisms, templates, pages — in React, Svelte, or any UI framework. Triggers on 'atomic design', 'component structure', 'atoms molecules organisms', 'component folder layout'."
---

# Skill: Atomic Design

[Brad Frost's atomic design](https://bradfrost.com/blog/post/atomic-web-design/) structures a UI as
five tiers, each composed of the ones below it. It is framework-agnostic — the tiers are about
_composition and responsibility_, not about any particular library.

## The five tiers

| Tier          | What it is                                          | Examples                          |
| ------------- | --------------------------------------------------- | --------------------------------- |
| **Atoms**     | Single-purpose, no composition; the smallest units  | `Button`, `Input`, `Icon`, `Tag`  |
| **Molecules** | A small group of atoms working as one unit          | `Card`, `Form`, `SearchBar`       |
| **Organisms** | A distinct page section built from molecules        | `Header`, `Footer`, `Hero`        |
| **Templates** | A page-level layout with placeholder content        | `BaseLayout`, `DashboardTemplate` |
| **Pages**     | A template bound to real data, routed to by the app | `UserProfile`, `UserList`         |

## Rules

- **Lowest tier that fits** — place a component at the lowest tier that describes it; only promote
  it when it genuinely composes the tier below.
- **Compose downward only** — a tier imports from the tier below it, never above. An atom never
  imports an organism; a molecule never imports a template.
- **Colocate** — a component's markup, styles, test, and story live together in the component's
  directory, with a barrel `index` re-export.
- **Name by intent** — `UserCard`, not `Card2`. PascalCase for component files; the framework's
  route-file convention (kebab-case) applies only inside the routing directory.

## Structure (framework-agnostic)

```
components/
├── atoms/          ← single-purpose (Button, Input, Icon)
│   └── Button/
│       ├── Button.<ext>       ← the component
│       ├── Button.test.<ext>  ← unit test
│       ├── Button.stories.<ext>  ← optional story
│       └── index.<ext>        ← barrel re-export
├── molecules/      ← atom groups (Card, Form)
├── organisms/      ← page sections (Header, Footer)
├── templates/      ← layout compositions (BaseLayout)
└── pages/          ← template + data (UserProfile)  [see mapping]
```

### Mapping to a framework

- **React (Next.js App Router)** — components live in `src/components/<tier>/<Name>/`. The `app/`
  route files (`page.tsx`) already play the **pages** role, so a separate `components/pages/` tier
  is optional — keep page composition in the route.
- **Svelte (SvelteKit)** — reusable components live in `src/lib/components/<tier>/<Name>/`. A page
  is a `+page.svelte` (or a component it renders) under `src/routes/`; page-specific components
  colocate with the page under `src/pages/<feature>/<page>/components/`.

## React examples

```tsx
// src/components/atoms/Button/Button.tsx
import type { ButtonHTMLAttributes } from "react";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary";
}

export const Button = ({ variant = "primary", ...props }: ButtonProps) => <button className={`btn btn--${variant}`} {...props} />;
```

```tsx
// src/components/molecules/Card/Card.tsx
import { ReactNode } from "react";

export const Card = ({ title, children }: { title?: string; children: ReactNode }) => (
  <div className="card">
    {title && <h3 className="card__title">{title}</h3>}
    {children}
  </div>
);
```

```tsx
// src/components/organisms/Header/Header.tsx
import { Navbar } from "../../molecules/Navbar";

export const Header = () => (
  <header className="header">
    <Navbar />
  </header>
);
```

```tsx
// src/components/templates/BaseLayout/BaseLayout.tsx
import { ReactNode } from "react";
import { Header } from "../../organisms/Header";
import { Footer } from "../../organisms/Footer";

export const BaseLayout = ({ children }: { children: ReactNode }) => (
  <div className="layout">
    <Header />
    <main>{children}</main>
    <Footer />
  </div>
);
```

## Svelte examples

```svelte
<!-- src/lib/components/atoms/Button/Button.svelte -->
<script lang="ts">
  import type { Snippet } from "svelte";

  let { variant = "primary", children, ...rest }: { variant?: "primary" | "secondary"; children: Snippet } = $props();
</script>

<button class="btn btn--{variant}" {...rest}>{@render children()}</button>
```

```svelte
<!-- src/lib/components/molecules/Card/Card.svelte -->
<script lang="ts">
  import type { Snippet } from "svelte";

  let { title, children }: { title?: string; children: Snippet } = $props();
</script>

<div class="card">
  {#if title}<h3 class="card__title">{title}</h3>{/if}
  {@render children()}
</div>
```

```svelte
<!-- src/lib/components/organisms/Header/Header.svelte -->
<script lang="ts">
  import Navbar from "$lib/components/molecules/Navbar/Navbar.svelte";
</script>

<header class="header">
  <Navbar />
</header>
```

```svelte
<!-- src/lib/components/templates/BaseLayout/BaseLayout.svelte -->
<script lang="ts">
  import type { Snippet } from "svelte";
  import Header from "$lib/components/organisms/Header/Header.svelte";
  import Footer from "$lib/components/organisms/Footer/Footer.svelte";

  let { children }: { children: Snippet } = $props();
</script>

<div class="layout">
  <Header />
  <main>{@render children()}</main>
  <Footer />
</div>
```

## Gotchas

- **Don't force it** — if a component doesn't clearly sit in a tier, keep it nearest its use until it
  does; the tiers are a guide, not a quota.
- **Templates vs pages** — a template has no real data; the page is where a template meets a
  route/loader and real content.
- **Framework routing wins** — Next.js `app/` and SvelteKit `src/routes/` own routing; atomic design
  structures the _components_ those routes render, not the routes themselves.
