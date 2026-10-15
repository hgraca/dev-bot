---
date: 2026-10-13
keywords: ["github", "github-pages", "org-root", "baseurl"]
trigger-on: ["github-pages-org-site", "github-pages-repo-naming", "pages-baseurl"]
---

## An org-root Pages site requires a repository literally named `<org>.github.io`

GitHub Pages serves an organisation's site at `https://<org>.github.io/` only from a repository named exactly `<org>.github.io`; any other repo owned by the org (e.g. `GET-E/get-e`) is a **project** site served at `https://<org>.github.io/<repo>/` no matter who owns it or what its README claims. So an "org-level umbrella at get-e.github.io" implies renaming the repo to `GET-E/get-e.github.io` (or creating that repo) — check before designing around an org root with `gh api repos/<org>/<repo> --jq .has_pages` and `gh api repos/<org>/<org>.github.io` (404 means it does not exist). A Pages workflow stays correct under either topology if it builds with `--baseurl "${{ steps.pages.outputs.base_path }}"`: empty for an org-root site, the repo name for a project site.
