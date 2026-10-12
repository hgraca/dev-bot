---
name: devbot:storybook-deploy
description: "Use when deploying a Storybook build to a static host. Triggers on 'deploy storybook', 'publish storybook', 'host storybook', 'storybook github pages'."
---

# Skill: Storybook Deploy

Deploying Storybook is two jobs: **build** it as a static site, then hand that static
site to a **host**. This skill owns the generic half — the build and the target-agnostic
rules — and routes the host-specific half to an annex. Adding a host is a new annex plus
a new row in the table below, never a change to this file.

## Prerequisite: a Storybook that builds

The host steps assume Storybook is already wired up with a `build-storybook` script.
Check both before going further:

```bash
# is the script present?
grep '"build-storybook"' package.json

# does it actually build?
npm run build-storybook
```

If Storybook is not installed yet, initialise it first (`npx storybook@latest init`) —
that is setup, this skill is deployment.

## The build

`npm run build-storybook` compiles every story into a self-contained static web app
(HTML/CSS/JS) that any web server serves — no Node runtime required. It writes to
`storybook-static/` by default. Preview it locally before deploying:

```bash
npx http-server storybook-static
```

The output directory is the artefact every host consumes. If the `build-storybook`
script overrides it (`npm run build-storybook -- -o <dir>` / `--output-dir`), the host's
upload path must match that directory, not the default.

## Choosing a target

Pick the host, then read only its annex:

| Target       | Read                      |
| ------------ | ------------------------- |
| GitHub Pages | `annexes/github-pages.md` |

More hosts (Netlify, S3, Vercel, Chromatic) are added as further annexes under
`annexes/` — the core never changes.

## Rules that hold for every target

- **Never commit the build output.** Add the output dir (`storybook-static/`) to
  `.gitignore`; it is generated, and the host rebuilds it from source.
- **Build in CI, not on a laptop.** Every target's flow builds Storybook in the pipeline
  and publishes that artefact, so the published site always matches the commit.
- **Serving under a subpath.** The Storybook app builds with relative paths, so its
  output works under a path prefix (`https://<host>/<repo>/`) without extra config.
  Assets served from `staticDirs` (or referenced by absolute URL) must be relative too,
  or they 404 under a prefix. If the builder still emits absolute paths, set the base in
  the builder — `viteFinal` → `base`, `webpackFinal` → `publicPath` — `storybook build`
  has no `--base` flag.

## Gotchas

- **A local build is not a deployment.** `build-storybook` on its own publishes nothing;
  the target's publish step is what puts it online. Never report "deployed" off a local
  build.
- **The script must exist.** Every target runs `npm run build-storybook`; if the script
  is missing, CI fails before it reaches any deploy step.
- **Output-dir drift.** When the output dir is customised, the host's upload path has to
  match it, or the upload finds nothing and the published site 404s.
