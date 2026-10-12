---
name: github-pages
description: "GitHub Pages deployment for Storybook — the GitHub Actions workflow and its GitHub-specific gotchas. Read this annex when hosting a Storybook build on GitHub Pages."
---

# GitHub Pages

GitHub Pages publishes a static site straight from a workflow — no server and no
`gh-pages` branch to maintain. This annex wires the Storybook static build from
`devbot:storybook-deploy` to it. Storybook's own
[publish docs](https://storybook.js.org/docs/sharing/publish-storybook#github-pages)
ship a GitHub Pages example that builds and uploads with no base config.

## Annex of `devbot:storybook-deploy`

This file is an annex of the `devbot:storybook-deploy` skill. Read it only when the
target host is GitHub Pages; the generic build and the target-agnostic rules stay in
`devbot:storybook-deploy`.

## Prerequisite — set the Pages source to GitHub Actions

The workflow cannot enable Pages on its own. Once, in the repository: **Settings → Pages
→ Build and deployment → Source = GitHub Actions**. Skipping this makes the
`deploy-pages` step fail with "Get Pages site failed" — the workflow file alone is not
enough.

## The workflow

Add `.github/workflows/deploy-storybook.yml`:

```yaml
name: Deploy Storybook
on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run build-storybook
      - run: touch storybook-static/.nojekyll
      - uses: actions/upload-pages-artifact@v3
        with:
          path: storybook-static
      - id: deployment
        uses: actions/deploy-pages@v4
```

On every push to `main`: `npm ci` installs, `npm run build-storybook` produces
`storybook-static/`, the artifact is uploaded, and `deploy-pages` publishes it to the
`github-pages` environment. The live URL is `steps.deployment.outputs.page_url`.

## Gotchas

- **`touch storybook-static/.nojekyll` is a no-op here, kept deliberately.** Under the
  Actions-artifact flow GitHub Pages serves the uploaded artifact directly and never runs
  Jekyll, so `.nojekyll` is unnecessary — it only matters for branch-based (`gh-pages`)
  publishing. It is harmless, so the workflow carries it.
- **Pages source must be "GitHub Actions".** If the repo is still set to "Deploy from a
  branch", `deploy-pages` fails before publishing anything. See the prerequisite above.
- **Copied onto a project that isn't npm/`storybook-static`.** The steps assume `npm ci`,
  a `build-storybook` script, and the default output dir. Swap in `pnpm`/`yarn`, and point
  `upload-pages-artifact`'s `path` at the real output dir if `build-storybook` overrides
  it.
- **No `concurrency` group.** Two quick pushes to `main` can race their deployments. Add
  a `concurrency: { group: "pages", cancel-in-progress: false }` block if that matters.
- **The upload reads the working tree, not git.** `upload-pages-artifact` packages
  `storybook-static/` straight from the runner, so gitignoring it (see the core rules in
  `devbot:storybook-deploy`) does not stop the deploy.
