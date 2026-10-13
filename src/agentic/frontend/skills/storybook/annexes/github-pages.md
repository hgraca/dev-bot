---
name: github-pages
description: "GitHub Pages deployment for a Storybook — the GitHub Actions workflow and its GitHub-specific gotchas. Read this annex when hosting a Storybook (or a documentation site containing one) on GitHub Pages."
---

# GitHub Pages

GitHub Pages publishes a static site straight from a workflow — no server and no `gh-pages` branch
to maintain. This annex wires the Storybook static build from `devbot:storybook` to it. Storybook's
own [publish docs](https://storybook.js.org/docs/sharing/publish-storybook#github-pages) ship a
GitHub Pages example.

## Annex of `devbot:storybook`

This file is an annex of the `devbot:storybook` skill. Read it only when the target host is GitHub
Pages; the generic build and the target-agnostic rules stay in `devbot:storybook`.

## Prerequisite — set the Pages source to GitHub Actions

The workflow cannot enable Pages on its own. Once, in the repository: **Settings → Pages → Build and
deployment → Source = GitHub Actions**. Skipping this makes the `deploy-pages` step fail with
"Get Pages site failed" — the workflow file alone is not enough.

## The workflow, when the Storybook lives inside a documentation site

This is the shape to use when the Storybook is built into `docs/storybook/` (see the parent skill):
the job builds the Storybook, then the site, then uploads the site's output.

```yaml
name: Deploy docs to GitHub Pages

on:
  push:
    branches: ["main"]
    paths:
      - "docs/**"
      - "src/components/**"
      - "src/pages/**"
      - "lib/shadcn/**"
      - ".storybook/**"
      - "vite.config.ts"
      - "package.json"
      - "pnpm-lock.yaml"
      - ".github/workflows/jekyll-gh-pages.yml"
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 11
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm build-storybook # → docs/storybook/
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
          working-directory: docs
      - id: pages
        uses: actions/configure-pages@v5
      - run: bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"
        working-directory: docs
        env:
          JEKYLL_ENV: production
      - uses: actions/upload-pages-artifact@v3
        with:
          path: docs/_site

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

The Storybook must be built **before** the site: the site generator copies `docs/storybook/` into
its output, and a component-list generator reads `docs/storybook/index.json`.

### Publishing the Storybook on its own

Without a surrounding site, drop the Ruby/Jekyll steps, build with `pnpm build-storybook`, and point
the upload at the Storybook output directory instead of `docs/_site`:

```yaml
- uses: actions/upload-pages-artifact@v3
  with:
    path: docs/storybook
```

## Gotchas

- **Pages source must be "GitHub Actions".** If the repository is still set to "Deploy from a
  branch", `deploy-pages` fails before publishing anything. See the prerequisite above.
- **`configure-pages` + `--baseurl`.** Project sites are served from
  `https://<org>.github.io/<repo>/`, not the domain root. Pass
  `--baseurl "${{ steps.pages.outputs.base_path }}"` (or the framework's equivalent) so every asset
  and link resolves; omitting it produces a site that loads nothing but 404s.
- **The `paths` filter decides what the site can go stale on.** List every directory the published
  artefact is built from — the documentation sources and the component folders are the usual pair.
  A directory left out means edits to it deploy only on the next unrelated change, and the published
  site silently disagrees with the commit that produced it.
- **The upload reads the working tree, not git.** `upload-pages-artifact` packages the directory
  straight from the runner, so gitignoring the build output (which you must) does not stop the
  deploy.
- **No `concurrency` group lets two quick pushes race.** Set
  `concurrency: { group: "pages", cancel-in-progress: false }` so a later deploy cannot land before
  an earlier one.
- **`touch <output>/.nojekyll` is a no-op under the artifact flow.** GitHub Pages serves the uploaded
  artefact directly and never runs Jekyll, so `.nojekyll` is unnecessary; it only matters for
  branch-based (`gh-pages`) publishing.
