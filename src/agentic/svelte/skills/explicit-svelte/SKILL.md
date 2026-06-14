---
name: explicit-svelte
description: "Svelte 5 + SvelteKit + TypeScript development conventions. Use this skill whenever building, scaffolding, or modifying any Svelte project — covers scaffolding, routing, atomic component design, ports/adapters architecture, SMUI theming, server vs client code separation, TypeScript rules, and data access patterns. Triggers on 'svelte', 'sveltekit', 'create svelte app', 'svelte component', 'svelte project', or when working in a Svelte codebase."
---

# Skill: Svelte 5 + SvelteKit + TypeScript

This skill provides conventions for Svelte 5, SvelteKit, and TypeScript, including:

- Atomic component design (atoms, molecules, organisms, templates)
- Ports/adapters architecture for business logic
- SMUI theming and token-based styling
- Explicit server/client code separation
- Strict TypeScript typing
- Data access patterns

---

## When to Apply

- Scaffold new SvelteKit projects
- Create components, routes, or server endpoints
- Add SMUI or theming
- Structure business logic (ports, adapters, services)
- Write TypeScript in a Svelte context
- Discuss Svelte conventions, patterns, or file placement

---

## Core Principles

- **SSR/SSG First**: Prioritize server-side rendering and static generation for performance and SEO.
- **Minimal Client-Side JS**: Reduce client-side JavaScript through server-side logic.
- **TypeScript Strict**: Always use `"strict": true` in `tsconfig.json`.
- **Functional & Declarative**: Follow functional and declarative programming patterns.
- **Accessibility**: Ensure semantic HTML and ARIA compliance.

---

## Further rules and practices

Next to this skill, also load the following skills:

- `svelte`
- `sveltekit-structure`
- `svelte5-best-practices`

---

## Scaffolding

### Initial Setup

Run once to create the project:

```bash
npx sv create <project-name>
```

Select: `minimal` template, TypeScript strict, SSR yes, Vitest/Playwright optional, Prettier, ESLint.

```bash
cd <project-name>
npm install
npm run dev
```

Set `"strict": true` in `tsconfig.json`.

---

## Project Structure

### Atomic Design

Use [Brad Frost's atomic design](https://bradfrost.com/blog/post/atomic-web-design/) for components
(`src/lib/components`, atoms → molecules → organisms → templates),
ports & adapters (`src/modules/User/UserRepository.ts` and its `adapters/`),
and Token-Based theming (`style/`):

```
src/
    routes/
    lib/
        components/         → generic components, reusable across pages
            atoms/          → single-purpose (Button, Input, Tag)
            molecules/      → atom groups (Card, Alert, LinkGroup)
            organisms/      → page sections (Header, Footer, Hero)
            templates/      → layout compositions (PageTemplate)
        services/           → generic services, reusable anywhere
    modules/            → types, rules (User, Project, Billing, ...)
        User/
            User.ts             → main data entity
            UserService.ts      → orchestration logic, entry point from the pages
            UserRepository.ts   → interface contracts for data access
            adapters/
                db/             → UserRepository DB implementation (user-repository-db.ts)
                api/            → UserRepository API implementation (user-repository-api.ts)
        Billing/
        Project/
        ...
    services/
    pages/
        user-management/
            profile/
                UserProfile.svelte      → the actual page to be rendered
                components/             → .svelte components rendered only used in this page
                    Avatar.svelte
                    FormFields.svelte
            list/
                UserList.svelte
                components/
            ...
        billing/
            ...
        ...
    style/
        semantic-tokens.ts  → named tokens used in components and pages (references primitives)
        primitives.ts       → palette (everything available, same for ALL themes: colors, spacing, typography)
        themes/
            index.ts        → exports all themes, for convenience when importing themes in pages
            light-theme.ts  → maps semantic tokens → primitives (light mode mappings)
            dark-theme.ts   → maps semantic tokens → primitives (dark mode mappings)
```

### Ports & Adapters

- **Ports**: Define interfaces for business logic (e.g., `UserRepository.ts`).
- **Adapters**: Implement ports for specific data sources (e.g., `adapters/db/UserRepository.ts`).
- **Swapping Data Sources**: Write a new adapter; no service or UI changes needed.

### Themes

Themes mapping:

```
primitives.ts (global palette: colors.white, colors.blue[400], colors.blue[500], colors.gray[900], spacing[4], spacing[8])
    ↓
light-theme.ts: { color: { primary: colors.blue[500], background: colors.white }, spacing: { primary: spacing[4], secondary: spacing[8] } }
dark-theme.ts:  { color: { primary: colors.blue[400], background: colors.gray[900] }, spacing: { primary: spacing[4], secondary: spacing[8] } }
    ↓
semantic-tokens.ts → just exports themeStore (used in components: `$themeStore.color.primary`)
```

Example:

```ts
// style/primitives.ts
export const colors = {
    white: "#FFFFFF",
    blue: { 500: "#0066FF", 400: "#0055EE" },
    gray: { 900: "#111111" },
};
export const spacing = { 4: "4px", 8: "8px" };
```

```ts
// style/themes/light-theme.ts
import { colors, spacing } from "../primitives.ts";

export const lightTheme = {
    color: {
        primary: colors.blue[500],
        background: colors.white,
    },
    spacing: {
        primary: spacing[4],
        secondary: spacing[8],
    },
};
```

```ts
// style/themes/dark-theme.ts
import { colors, spacing } from "../primitives.ts";

export const darkTheme = {
    color: {
        primary: colors.blue[400],
        background: colors.gray[900],
    },
    spacing: {
        primary: spacing[4],
        secondary: spacing[8],
    },
};
```

```ts
// style/themes/index.ts
export { lightTheme } from "./light-theme.ts";
export { darkTheme } from "./dark-theme.ts";
```

```ts
// semantic-tokens.ts
// semantic-tokens.ts
import { writable } from "svelte/store";
import { lightTheme, darkTheme } from "./themes/index.ts";

const storedTheme = localStorage.getItem("theme") || "light";
export const themeStore = writable(storedTheme === "dark" ? darkTheme : lightTheme);

export function toggleTheme() {
    themeStore.update((current) => {
        const next = current === lightTheme ? darkTheme : lightTheme;
        localStorage.setItem("theme", next === darkTheme ? "dark" : "light");
        return next;
    });
}
```

Then we use Svelte stores for reactive theme switching:

```xhtml
<!-- App.svelte -->
<script>
    import { themeStore, toggleTheme } from "./style/semantic-tokens.ts";
</script>

<button onclick="{toggleTheme}">Toggle Theme</button>
```

### Styling

## Styling

- **SMUI Only**: Use `@smui/*`; avoid `@mui/*`, `bits-ui`, `melt-ui`, or `ark-ui`.
- **Token-Based Theming**: Use `src/style/` for primitives, themes, and semantic tokens.
- **Scoped Styles**: Use Svelte's `<style>` tags; keep styles co-located with components.

---

## Svelte 5 Runes

- **`$state`**: Reactive state
- **`$derived`**: Computed values
- **`$effect`**: Side effects
- **`$props`**: Component properties
- **`$bindable`**: Two-way binding
- **`$inspect`**: Debugging

### Common Mistakes

- ❌ `let count;` → ✅ `let count = $state(0);`
- ❌ `$effect` for derived values → ✅ `$derived`
- ❌ `on:click` → ✅ `onclick`
- ❌ `createEventDispatcher` → ✅ Callback props
- ❌ `<slot>` → ✅ Snippets with `{@render}`

---

## SvelteKit Features

### Routing

- Use file-based routing in `src/routes/`.
- **`+` prefix required**: Files without it are ignored.
- **Server Code**: `+server.ts`, `+page.server.ts`, `src/lib/server/...` are blocked from `.svelte` imports.

### Load Functions

- Use `+page.server.ts` for server-side data loading.
- Avoid sequential `await`s; use `Promise.all` for parallel requests.

### Form Actions

- Use form actions for mutations.

---

## TypeScript

- **Strict Mode**: Always scaffold with `"strict": true`.
- **Props Typing**: Use `$props()` for component properties.
- **Generic Components**: Type props and generic components explicitly.

---

## State Management

- Use Svelte runes (`$state`, `$derived`) for local state.
- Use stores for shared state.
- Avoid module-level state in SSR to prevent cross-request leaks.

---

## Implementation Roadmap

1. **Module Definitions**: Entity, port contract, service.
2. **Adapters**: DB and API adapters inside each module.
3. **Style Foundations**: Primitives, themes, semantic tokens.
4. **SvelteKit Routes**: Serve pages with `+page.server.ts`.
5. **Page Components**: Wire modules to UI.
6. **Atomic Components**: Build atoms, molecules, organisms.
7. **SMUI Integration**: Wire SMUI components into the design system.
8. **Input Validation**: Validate at module boundaries.
9. **Deploy**: Use `adapter-node` for server-rendered prototypes.

---

## Deployment

- **Default**: `adapter-node` for server-rendered prototypes.

```bash
npm install -D @sveltejs/adapter-node
```

`svelte.config.js`:

```js
import adapter from "@sveltejs/adapter-node";

export default {
    kit: {
        adapter: adapter(),
    },
};
```

- **Static**: Use `adapter-static` only if the app is fully pre-rendered.

---

## Testing

- Use **Vitest** for unit testing.
- Use **Lighthouse** for performance auditing.
- Write comprehensive component tests.

---

## Performance

- Focus on **Web Vitals** optimization.
- Minimize client-side JavaScript.
- Use preloading for faster navigation.
- Implement lazy loading where appropriate.

---

## Gotchas

- **Server/Client Split**: Server code is invisible to the client.
- **Theme ≠ Business Logic**: Keep themes in `src/style/`.
- **`$lib` Alias**: Use `$lib` for `src/lib/` imports; for `src/modules/`, use relative paths or configure a `$modules` alias.
- **SMUI Only**: Never use non-SMUI UI libraries.
- **Svelte 5 Syntax**: Use `onclick`, not `on:click`.
- **TypeScript Strict**: Set at scaffold to avoid hundreds of fix errors later.
- **Ports Before Adapters**: Define interfaces before implementations.
