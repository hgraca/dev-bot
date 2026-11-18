---
name: devbot:design-system
description: "Use when creating or extending a design system: the token contract, semantic CSS variables, light and dark modes, theme variants, scales and contrast floors. Triggers on 'design system', 'design tokens', 'CSS custom properties', 'dark mode', 'theme variant', 'type scale', 'contrast'."
---

# Skill: Design System

The from-scratch token system: one contract, one generator, every theme derived from it, and a
contrast gate that fails a build rather than shipping unreadable text.

This skill owns **creating** the system. For where components sit once it exists, see
`devbot:atomic-design`; for pulling tokens out of an interface that already exists (or critiquing
it), impeccable's `extract` / `critique` / `document` references.

## The contract

A design system that lives only in CSS has no place to run a check: contrast between two hex values
is a computation, and a stylesheet is not a good input for one. Keep the source of truth as data,
generate the CSS from it, and gate the generator.

```
tokens.json          ← the contract: palettes + semantic mapping + non-colour scales
  └─ build-tokens     ← resolves every theme, gates contrast, writes CSS
       └─ tokens.css  ← generated: :root, [data-theme="…"], .dark blocks — never hand-edited
```

The generated stylesheet is a build artifact: it belongs in `.gitignore` or in the repo with a
"generated, do not edit" header, and CI regenerates it so drift is impossible.

## Three layers of token

Never jump from a hex value to a component. A component asks for a purpose, the purpose maps to a
palette entry, the palette entry is a hex value — and only the middle layer changes per theme.

| Layer         | Example                                     | Changes per theme? |
| ------------- | ------------------------------------------- | ------------------ |
| **Primitive** | `palette.neutral.50`, `palette.brand.600`   | No                 |
| **Semantic**  | `--surface`, `--text-primary`, `--border-subtle`, `--focus-ring`, `--danger-text` | Yes |
| **Component** | `--button-primary-bg`                       | Rarely — add one only when a component genuinely needs its own knob |

Components consume **semantic** tokens only. A component that names a palette entry
(`bg-brand-600`) is a theme that cannot be re-pointed; one that names a purpose (`bg-brand`) is.

### Semantic names worth having

- Surfaces: `--surface`, `--surface-raised`, `--surface-sunken`, `--surface-inverse`
- Text: `--text-primary`, `--text-secondary`, `--text-muted`, `--text-inverse`, `--text-on-brand`
- Lines and focus: `--border-subtle`, `--border-strong`, `--focus-ring`
- Status, each with a readable-on pair: `--success` / `--on-success`, `--warning` / `--on-warning`,
  `--danger` / `--on-danger`, `--info` / `--on-info`
- Scales: `--radius-sm|md|lg`, `--space-1…`, `--text-xs…`, `--shadow-1…`, `--font-sans|mono`

Name by purpose, never by appearance. `--text-gray-500` survives exactly one redesign; `--text-muted`
is the token every theme can re-point.

## Themes are mappings, not palettes

Every theme resolves the **same** semantic names through a different mapping. Two consequences:

- **Light and dark are pairs**, not two independent designs. For every semantic token, both themes
  carry a value; a token with only a light value is a bug the dark pass will find as invisible text.
- **Dark is not inverted light.** Dark surfaces sit _above_ their canvas (`#141414` → `#1e1e1e`), not
  below it; shadows weaken (they read as haze), borders carry more of the separation, and saturated
  brand colours need a lighter step to stay legible on a dark ground.

A variant (`"mint"`, a seasonal campaign, a customer brand) is a palettes-and-mapping entry, never a
set of per-component overrides. If a variant needs a component change, the semantic layer is missing
a token.

### Scoping

```css
:root {
  /* light — the default */
}
.dark {
  /* same names, dark mapping */
}
[data-theme="mint"] {
  /* same names again; composes with .dark if the variant ships one */
}
```

Pick **one** switch mechanism and use it everywhere: a class on `<html>` (`.dark`) is what shadcn/ui,
Tailwind's dark variant and the Storybook toolbar expect; `[data-theme]` is easier to extend to more
than two themes and pairs naturally with variant switching. If the project follows system preference,
`prefers-color-scheme` seeds the initial class — resolve it once at boot, do not fight it in two
places, and set the class before first paint to avoid a flash of the wrong theme.

## The contrast gate

The gate is the reason the contract is data. Assert every pair the UI actually renders, and **fail the
build** when one misses. WCAG AA: **4.5:1** for body text, **3:1** for large text (≥ 24px, or ≥ 18.66px
bold) and for non-text UI boundaries that carry meaning (input borders, focus rings, chart strokes).

Compute relative luminance with the sRGB transfer function — a naive `0.2126R + 0.7152G + 0.0722B` on
8-bit channels is wrong by enough to pass unreadable pairs:

```ts
const channel = (c: number) => {
  const s = c / 255;
  return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};
const luminance = (hex: string) => {
  const [r, g, b] = parse(hex).map(channel) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const ratio = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
};
```

Enumerate the pairs explicitly — `text-primary` on `surface`, `surface-raised` and `surface-sunken`;
`text-muted` on every surface it appears on (this is the pair that fails first); each `on-*` on its
status colour; `border-strong` and `focus-ring` against both adjacent surfaces. Run the gate per
theme, including every variant and both modes.

```ts
for (const theme of themes) {
  for (const { fg, bg, min } of pairs) {
    const r = ratio(resolve(theme, fg), resolve(theme, bg));
    if (r < min) failures.push(`${theme.name}: ${fg} on ${bg} = ${r.toFixed(2)} < ${min}`);
  }
}
if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
```

Fix a failing pair by moving the _palette_ value, not by loosening the threshold, and record the
measured ratio next to the mapping so the next change starts from evidence.

## Wiring it to the components

The generated CSS defines the custom properties; the utility layer maps them to classes so no
component writes a raw value.

```css
/* Tailwind v4 — the theme block is the bridge; there is no tailwind.config.js */
@import "tailwindcss";
@import "./tokens.css";

@theme inline {
  --color-surface: var(--surface);
  --color-text-primary: var(--text-primary);
  --color-border-subtle: var(--border-subtle);
  --radius-md: var(--radius-md);
  --font-sans: var(--font-sans);
}
```

- **shadcn/ui** expects its own semantic names — `--background`, `--foreground`, `--card`,
  `--popover`, `--primary`, `--secondary`, `--muted`, `--accent`, `--destructive`, `--border`,
  `--input`, `--ring`, `--chart-1…`, `--sidebar-*`. Map your tokens onto those names in the tokens
  layer rather than renaming your system to match a library; `--primary` becomes `var(--brand)` and
  `--foreground` becomes `var(--text-primary)`.
- **daisyUI** themes carry `--color-*` variables (`--color-base-100`, `--color-primary`,
  `--color-base-content`, …; older majors use `--b1`, `--p`, …). Declare a daisyUI theme per variant
  and point each variable at your semantic token, so `bg-base-100` and `bg-surface` are the same
  colour by construction. Check the installed major's variable names before writing the block.
- **Nothing downstream hardcodes**: no `text-[13px]`, no `rounded-[2px]`, no `bg-[#ff00ff]`, no raw
  palette class like `bg-neutral-800`, no `ring-base-content`-style shortcuts that bypass the semantic
  layer. If a scale has no step for the value you want, add the step — do not inline the value. The
  module's design detector hook flags exactly these on every UI edit; a finding is a token that is
  missing, not a warning to silence.

## Process

1. **Collect the modes and surfaces** — how many themes (light, dark, variants), and which surfaces
   exist (canvas, raised card, sunken well, inverse). Write them down before choosing colours.
2. **Lay the palettes** — a neutral ramp plus brand, status and accent ramps, each with enough steps
   (50–950 in the Tailwind idiom) that every semantic token has a plausible source in every theme.
3. **Map the semantics** — every name in the table above, for every theme. This is the design work,
   not the palette: `--text-muted` is a _decision_ about how quiet secondary copy may get.
4. **Gate** — run the contrast pairs per theme, fix at the palette, re-run.
5. **Generate** the CSS and wire the utility layer (`@theme inline`, shadcn names, daisyUI theme).
6. **Switch it** — one mechanism, applied before first paint, persisted per user; the toggle lives in
   the app shell, not in every page.
7. **Verify by looking** — render every theme and both modes on a real page, side by side at the sizes
   the product ships (and at 200% zoom). Contrast maths passes pairs, not layouts: check that muted
   text is still quiet on the raised surface and that borders still separate.
8. **Prove it holds** — keep the gate in the build and the pairs in the contract, so the next palette
   change is checked instead of remembered.

## Gotchas

- **A gate that runs on the generated CSS proves nothing** — it reads values after the mapping you
  meant to check. Gate the contract.
- **Alpha compositing breaks the maths** — `rgba(0,0,0,0.4)` over an unknown surface has no fixed
  ratio. Resolve translucent tokens against the surface they sit on before measuring, or make them
  opaque.
- **Gradients are not a pair** — measure the lightest and darkest stop against the text colour and
  take the worst; better, do not put body text on a gradient.
- **`prefers-color-scheme` is a seed, not a second switch** — two mechanisms that both write the class
  produce a toggle that flips back on the next system change.
- **Status colours need an `on-` pair** — `--danger` as a _background_ with `--text-primary` on it is
  the classic AA failure; the pair belongs in the contract.
- **Dark mode collapses elevation** — three shadow levels that work on white read as smudges on
  `#141414`; raise surfaces instead of deepening shadows.
- **A token nobody consumes is not a token** — after the redesign, grep for orphan names and either
  wire them or delete them; dead tokens invite divergence.
- **Type and radius ramps drift per component** — an arbitrary size or radius in a component is the
  most common finding in review, and the reason the scales belong in the contract with the colours.
- **Adding a theme late exposes hardcoding** — the first variant run is the audit: every raw colour
  and every palette class surfaces. Budget for that pass.

## See also

- `devbot:atomic-design` — the component tiers once the tokens exist.
- `devbot:storybook` — a place to render every theme side by side.
- impeccable (`impeccable extract`, `impeccable document`) — harvesting tokens out of an interface
  that already exists, and writing the `DESIGN.md` the detector reads.
