---
name: devbot:storybook
description: "Use when building a Storybook, wiring it into a static documentation site, or publishing it to a host. Triggers on 'build storybook', 'storybook build', 'publish storybook', 'deploy storybook', 'host storybook', 'storybook github pages'."
---

# Skill: Storybook

Shipping Storybook is three jobs: **build** the workshop as a static site, **wire** it into the
project's documentation if there is one, then hand the result to a **host**. The build and the
target-agnostic rules live here; the host-specific half is an annex.

## Prerequisite: a Storybook that builds

The steps below assume Storybook is wired up with a `build-storybook` script. Check both before
going further:

```bash
grep '"build-storybook"' package.json
pnpm build-storybook
```

Initialising Storybook (`pnpm dlx storybook@latest init`) is setup, not deployment.

## The build

`build-storybook` compiles every story into a self-contained static app (HTML/CSS/JS) that any web
server serves — no Node runtime required. Point the output where it belongs:

```bash
storybook build -o docs/storybook
```

- **Inside the documentation site.** When the project has a static docs site (a Jekyll `docs/` tree,
  say), build the Storybook into a subdirectory of it rather than a directory of its own. The
  Storybook then ships as one site under a subpath (`/storybook/`) instead of a second deployment
  with its own URL and its own Pages configuration.
- **Expose it as make targets** so nobody has to remember the flags:

  ```make
  storybook-build:   ## build the Storybook only
  docs-build:        ## build the Storybook, then the documentation site
  docs:              ## build both and serve the site locally
  ```

- **Never commit the output.** Gitignore the build directory (`docs/_site/`, `docs/storybook/`,
  `docs/vendor/`); it is generated, and CI rebuilds it from source.
- **Preview it** with the project's serve target before publishing, not by opening the HTML file —
  the app needs to be served over HTTP.

## Themes

A light/dark token setup is only real if the reader can switch it inside the workshop. Register
`@storybook/addon-themes` and apply the token class in the preview:

```tsx
// .storybook/preview.tsx
import { withThemeByClassName } from "@storybook/addon-themes";

export const decorators = [
  withThemeByClassName({
    themes: { light: "", dark: "dark" },
    defaultTheme: "light",
  }),
];
```

The value on the right of each entry must be the exact class (or `data-*` attribute, via
`withThemeByDataAttribute`) the token stylesheet uses for that theme — `.dark` for a `.dark` block.
Getting it wrong is silent: the switcher appears and nothing changes. Adding a theme is one entry
here plus its token block; no component changes. Verify by reading the preview's computed custom
properties under each theme, not by eye.

## Wiring it into a static documentation site

When the project also ships docs, the Storybook is one section of that site:

- Build the Storybook into a subdirectory of the site (above), and serve it as a subpath.
- **Link it from the landing page and the navigation** — a Storybook nobody links to is invisible.
- **Generate the component list from the component folders**, and link each row to its Storybook
  entry. Resolve story ids from the **built** `storybook/index.json` rather than composing them from
  the title: the built index is the only source that is guaranteed to match, and it encodes the
  slug rules (case, separators, story suffix).
- **Leave the Storybook cell empty when a component has no story.** A component exists in the source
  the moment its folder does; its story may lag. An empty cell is honest; a guessed link 404s.
- A Jekyll site can do the generation with a small generator plugin in `_plugins/` — it runs on
  every build, local and CI, so the list cannot drift. (Local Jekyll plugins do not run in GitHub's
  hosted Pages build, which is safe-mode; they do run in an Actions build.)

## Choosing a target

Pick the host, then read only its annex:

| Target       | Read                      |
| ------------ | ------------------------- |
| GitHub Pages | `annexes/github-pages.md` |

More hosts (Netlify, S3, Vercel, Chromatic) become further annexes under `annexes/` — the core never
changes.

## Rules that hold for every target

- **Never commit the build output.** Add the output directory to `.gitignore`; the host rebuilds it
  from source.
- **Build in CI, not on a laptop.** Every target's flow builds Storybook in the pipeline and
  publishes that artefact, so the published site always matches the commit.
- **Serving under a subpath.** The Storybook app builds with relative paths, so its output works
  under a path prefix (`https://<host>/<repo>/`) without extra config. Assets served from
  `staticDirs` (or referenced by absolute URL) must be relative too, or they 404 under a prefix. If
  the builder still emits absolute paths, set the base in the builder — `viteFinal` → `base`,
  `webpackFinal` → `publicPath`; `storybook build` has no `--base` flag. Check the built
  `index.html` for a leading-slash `src`/`href` before trusting it.
- **The upload path must match the output directory.** When `build-storybook` overrides it
  (`-o <dir>`), the host's upload path has to point at that directory, not the default.

## Gotchas

- **A local build is not a deployment.** `build-storybook` on its own publishes nothing; the
  target's publish step is what puts it online. Never report "deployed" off a local build.
- **A missing `build-storybook` script fails CI before any deploy step** — every target runs it.
- **The theme switcher can appear without working.** The addon registers the toolbar item even when
  the decorator's class never matches a token block; check the computed variables, not the toolbar.
- **A docs site that builds the Storybook must build it first.** The site generator copies the
  Storybook directory into the published output, and a component-list plugin reads
  `storybook/index.json`; if the Storybook is not built before the site, the list renders with every
  Storybook cell empty.
