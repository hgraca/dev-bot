# Organisation docs-umbrella scaffold

A ready-to-copy Jekyll + Node site that publishes an **organisation-level documentation umbrella**:
one page at `https://<org>.github.io/` listing every project that opts in, each linking to its own
docs site.

This is the concrete form of `annexes/org-umbrella.md` in `devbot:gh-pages`. Read that annex first —
it explains the topology, the opt-in contract and the traps; this scaffold is the wiring.

## Prerequisite

The repository must be named exactly `<org>.github.io`. GitHub serves an org root only from that
name; any other repository is served at `https://<org>.github.io/<repo>/` instead.

## What goes where

| In this scaffold                       | Copy to                              |
| -------------------------------------- | ------------------------------------ |
| `docs/`                                | `<org>.github.io/docs/`              |
| `scripts/`                             | `<org>.github.io/scripts/`           |
| `.github/workflows/umbrella-pages.yml` | `<org>.github.io/.github/workflows/` |
| `.gitignore`                           | `<org>.github.io/.gitignore`         |

## Placeholders

| Placeholder  | Replace with                                                               |
| ------------ | -------------------------------------------------------------------------- |
| `<Org>`      | the organisation's display name (page titles)                              |
| `<Org Name>` | the copyright holder in the footer                                         |
| `<org>`      | the GitHub organisation slug (`<org>.github.io`, `github.com/<org>`)       |
| `<repo>`     | a project repository's name — the opt-in example's `docs_url`              |
| `your-org`   | the org default in `scripts/generate-projects.mjs` — or set `UMBRELLA_ORG` |

## How it works

The project list is generated at build time and never committed:

1. `scripts/generate-projects.mjs` enumerates the organisation's repositories;
2. reads each repository's `docs/umbrella-integration.json` from its default branch;
3. validates it, resolves the display name, and writes `docs/_data/projects.json` (gitignored);
4. Jekyll renders `docs/index.md` over that data.

A repository with no config is skipped **silently**; a config that exists but cannot be read or fails
validation is `WARN`ed and skipped — a broken sibling never fails the build.

## Manual setup (one-off, in GitHub)

1. Name the repository `<org>.github.io`.
2. Create an **organisation** Actions secret `UMBRELLA_TOKEN`: a fine-grained PAT with **Metadata:
   read** and **Contents: read**, repository access **All repositories**, resource owner the
   organisation.
3. Repository **Settings → Pages → Source = "GitHub Actions"**.

## Run it locally

```bash
GH_TOKEN="$(gh auth token)" make -C docs data   # generate docs/_data/projects.json
make -C docs serve                              # http://localhost:4000
node --test                                     # the generator's tests
```

`make -C docs build` produces a production build in `docs/_site`.

## Letting a project opt in

In the **project's** repository — not this one — add `docs/umbrella-integration.json`:

```json
{
  "$schema": "https://<org>.github.io/umbrella-integration.schema.json",
  "description": "One-line summary shown on the project card.",
  "docs_url": "https://<org>.github.io/<repo>/"
}
```

`description` and `docs_url` are required; `name`, `category` and `order` are optional. The file's
presence **is** the opt-in — nothing here changes. `docs/umbrella-integration.schema.json` in this
scaffold is the published contract; editors validate against it.

## Gotchas

- **Escape every interpolated field.** Liquid's `{{ }}` does not HTML-escape, and on a shared
  `<org>.github.io` origin one project's config reaches every sibling site. `docs/index.md` already
  applies `escape` to each field; keep that when editing it.
- **The scheduled run is the backstop.** A sibling's new opt-in appears on the next cron tick or a
  manual dispatch, because its push happened in another repository.
- **A rename never rebuilds.** Renaming the repository does not trigger Pages, so the old artifact
  keeps the previous base path — the page renders with content but no styling. Re-run the workflow.
- **Commit `Gemfile.lock`.** `ruby/setup-ruby`'s `bundler-cache` relies on it; generate it with
  `bundle install` in `docs/`.
- **`docs/_data/projects.json` is gitignored deliberately** — it is generated, and committing it
  would drift from the organisation.
- **Brand assets are placeholders.** `docs/assets/img/` ships a neutral logo pair and favicon;
  replace them with the organisation's.
