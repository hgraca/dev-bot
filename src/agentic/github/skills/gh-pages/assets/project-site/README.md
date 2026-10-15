# Project-site documentation scaffold

A ready-to-copy Jekyll site for **one repository's** documentation, published to GitHub Pages as a
**project site** at `https://<org>.github.io/<repo>/`.

This is the concrete form of Stage 5 of `devbot:gh-pages`. Read that skill first: it decides the
audience, the scope and the pages; this scaffold only wires them up.

## What goes where

| In this scaffold                        | Copy to                     |
| --------------------------------------- | --------------------------- |
| `docs/`                                 | `<repo>/docs/`              |
| `.github/workflows/jekyll-gh-pages.yml` | `<repo>/.github/workflows/` |

## Placeholders

| Placeholder      | Replace with                                         |
| ---------------- | ---------------------------------------------------- |
| `<Project Name>` | the project's display name (also the page `<title>`) |
| `<repo>`         | the repository name — this is the `baseurl`          |
| `<org>`          | the org or user that owns the repository             |
| `<Org Name>`     | the copyright holder shown in the footer             |
| `<...>`          | the matching prose, command, path or description     |

## Brand assets

`docs/assets/img/` ships **placeholder** logos and a favicon so the shell renders as-is. Replace all
three with the real brand assets: `logo-light.svg` (light theme), `logo-dark.svg` (dark theme) and
`favicon.svg`. Keep both logos — the topbar swaps them on `data-theme`.

## Joining the organisation umbrella

If the organisation runs a docs umbrella, keep `docs/umbrella-integration.json` and fill in its
placeholders. The file's presence on the default branch **is** the opt-in; delete it to stay out.
`name` is optional — omitting it falls back to the project manifest (`composer.json`, then
`package.json`), then the repository name.

## Build locally

```bash
cd docs
bundle install
bundle exec jekyll serve
```

`baseurl` is set, so the site is served at `http://localhost:4000/<repo>/` — check it under that
path, not at the root.

## Gotchas

- **`webrick` must stay in the `Gemfile`.** Ruby 3.x no longer bundles it, so `jekyll serve` fails
  locally without it.
- **`baseurl` must be `/<repo>`.** It is the repository name; empty or wrong means every asset and
  link 404s.
- **Set Pages Source = "GitHub Actions" once**, in repository settings. Left on "Deploy from a
  branch", GitHub's own build can overwrite the deploy with a root-relative one.
- **Commit what is generated, ignore what is built.** `Gemfile.lock` is committed; `_site/`,
  `.jekyll-cache/` and `vendor/` are gitignored by `docs/.gitignore`.
- **Resolve links with `relative_url`** in layouts, includes **and** markdown link destinations — a
  hand-written `/path/` 404s under the baseurl.
- **The bundler pin is local, not committed.** `docs/.bundle/config` (holding
  `BUNDLE_PATH: vendor/bundle`) is gitignored — create it if you want `bundle install` to write into
  `docs/vendor/bundle`. CI's `ruby/setup-ruby` sets the path itself.
