---
date: 2026-10-13
keywords: ["github", "github-pages", "jekyll", "baseurl", "deployment"]
aliases: ["pages deploy ignored", "legacy pages build", "branch build overwrites actions", "relative_url 404", "unstyled pages site"]
trigger-on: ["github-pages-source"]
---

## A GitHub Pages branch build silently overwrites your Actions deployment and uses an empty baseurl

With a repo's Pages *Build and deployment → Source* left on **Deploy from a branch** (the default), GitHub runs its own `pages-build-deployment` (the `jekyll-build-pages` action) on every push to that branch and deploys the result — even when a working `actions/deploy-pages` workflow also runs. The branch build ignores your workflow's flags and honours only the repo's `_config.yml`, so a project site whose `baseurl` is left empty emits root-relative links: `{{ '/assets/css/site.css' | relative_url }}` becomes `/assets/css/site.css`, which on `https://<org>.github.io/<repo>/` resolves to the domain root and 404s. The symptom is a live-but-unstyled site — and, if the branch build can't run your asset pipeline, a missing generated sub-site (e.g. a Storybook) — while your own workflow log shows a correct `--baseurl` build that appears to succeed. Diagnose with `gh api repos/<o>/<r>/pages` → `build_type: "legacy"` (vs `"workflow"`), and compare the newest `.../pages/builds` entry against your workflow's run times. Fix by setting *Source = GitHub Actions*; note a source change alone does not redeploy, so trigger the workflow once. Harden by pinning `baseurl` in the site config (correct links under either build), overriding it locally (e.g. `--baseurl ""`) if the local preview is served at the root.
