---
name: org-umbrella
description: "The org-level documentation umbrella: one index site at the organisation root listing every project that opts in with docs/umbrella-integration.json. Read this when the site indexes the organisation rather than documenting one project."
---

# Org-level documentation umbrella

An **umbrella** is one small site at the organisation root — `https://<org>.github.io/` — that lists
every project publishing documentation, each linking to that project's own docs site. It is an
**index**, not a host: it never renders another project's content, only a card per project. Each
project keeps its own Jekyll site (see Stage 5 of `devbot:gh-pages`).

The defining difference from the project site the parent skill builds:

|                | Project site                      | Org umbrella                         |
| -------------- | --------------------------------- | ------------------------------------ |
| URL            | `https://<org>.github.io/<repo>/` | `https://<org>.github.io/`           |
| `baseurl`      | `/<repo>`                         | `""` (empty)                         |
| Repository     | any repo                          | literally `<org>.github.io`          |
| Page set       | the project's documentation       | one page listing other projects      |
| Content source | authored markdown                 | generated from the org at build time |

## Annex of `devbot:gh-pages`

This file is an annex of the `devbot:gh-pages` skill. The five-stage process (audience → information
→ scope → write → scaffold) and the project-site scaffold live in `devbot:gh-pages`; this annex
covers only the org-level topology.

## When an umbrella is the right call

- **Many projects, each already publishing its own docs site.** The umbrella answers "where is
  everything?" in one place, and adding a project never means touching the umbrella.
- **Not for a single project.** One project gets a project site under its own `baseurl` — an
  umbrella listing exactly one card is overhead with a second repo to maintain.
- **The umbrella is its own repository.** It is not a section of a project's `docs/` tree.

## Topology and naming (MUST)

- **The org root requires a repository named exactly `<org>.github.io`.** GitHub Pages serves
  `https://<org>.github.io/` only from that repository; every other repo the org owns is a **project**
  site at `https://<org>.github.io/<repo>/`, no matter who owns it. Verify before designing around an
  org root:

  ```bash
  gh api repos/<org>/<org>.github.io --jq .has_pages   # 404 → it does not exist yet
  ```

- **`baseurl: ""` in the umbrella's `_config.yml`** — it is served from the domain root. A project
  site sets `baseurl: "/<repo>"`. Getting this wrong is the single most common source of 404s.
- **Keep the workflow topology-agnostic.** Pass `--baseurl "${{ steps.pages.outputs.base_path }}"`
  to `configure-pages`/Jekyll so the same workflow is correct whether the repo serves the org root
  (empty base path) or a project path (the repo name).

## The opt-in contract — one file per project

A project appears in the umbrella **only if** its repository contains
`docs/umbrella-integration.json` on its default branch. **Presence of the file is the opt-in** — no
umbrella-side change is ever needed to add, remove, or rename a project.

| Key           | Required | Meaning                                                               |
| ------------- | -------- | --------------------------------------------------------------------- |
| `description` | yes      | One-line summary on the project card.                                 |
| `docs_url`    | yes      | Absolute `http(s)` URL of the project's documentation site.           |
| `name`        | no       | Display name; falls back to the project manifest, then the repo name. |
| `category`    | no       | Grouping label; used as a section heading when present.               |
| `order`       | no       | Sort weight; lower first.                                             |
| `$schema`     | no       | JSON Schema pointer — accepted and ignored.                           |

**Unknown keys are rejected**, so the contract is closed: a typo in a key drops the project with a
warning rather than silently doing nothing.

```json
{
  "$schema": "https://<org>.github.io/umbrella-integration.schema.json",
  "description": "One-line summary shown on the project card.",
  "docs_url": "https://<org>.github.io/<repo>/"
}
```

Publish the contract as a JSON Schema (`$id` = `https://<org>.github.io/umbrella-integration.schema.json`,
draft 2020-12, `additionalProperties: false`) so every project's editor validates the file as it is
written. Declare `name` only when the manifest cannot supply one.

## Build-time aggregation

The project list is **never committed** — it is generated on every build, so it cannot drift from the
org. A zero-dependency Node ESM script does the work before Jekyll runs:

1. **Enumerate the org** — `GET /orgs/<org>/repos?per_page=100&type=all`, following pagination;
   skip `archived` and `disabled` repos.
2. **Read each candidate's config** from its default branch via the Contents API with
   `Accept: application/vnd.github.raw` — `GET /repos/<org>/<repo>/contents/docs/umbrella-integration.json?ref=<branch>`.
3. **Classify the response** — `404` means "not opted in" and is skipped **silently** (a warning per
   non-participating repo would be noise); a config that exists but cannot be read (non-404) or fails
   validation gets a `WARN:` naming the repo and is skipped. **The build never fails on a bad
   sibling** — one malformed config must not take the whole umbrella down.
4. **Resolve the display name** — config `name` → project manifest (`composer.json`, then
   `package.json`; strip the `owner/` scope, split on `-`/`_`/space, title-case) → repository name.
   Never hardcode a project→name map: a repo named `core` whose `composer.json` says `acme/transfers`
   appears as **Transfers** with no config field at all.
5. **Normalise and sort** — store `docs_url` as `new URL(value).href` (percent-encoding anything
   attribute-breaking), then sort by `order` ascending (absent last), then by name.
6. **Write `docs/_data/projects.json`**, gitignored, alongside `_config.yml`, before Jekyll builds.

Keep the generator's pure helpers (validation, name resolution, entry shaping, sorting) in a separate
module with `node:test` coverage — that is the part with logic worth testing, and the CI job runs
`node --test` before building.

## Rendering the index

`docs/index.md` groups `site.data.projects` by `category` into a card grid, and renders an empty
state when nothing has opted in yet.

**Escape every interpolated field.** Liquid's `{{ }}` does not HTML-escape, so any value from
`_data/*.json` — ultimately written by other repositories — is injected verbatim:

```liquid
{%- for project in group.items -%}
<a class="card" href="{{ project.docs_url | escape }}">
  <span class="card-name">{{ project.name | escape }}</span>
  <span class="card-desc">{{ project.description | escape }}</span>
</a>
{%- endfor -%}
```

On a shared `<org>.github.io` origin a single unescaped field reaches **every sibling project site**,
not just the umbrella. Validation and output-encoding are separate controls: confirming a value is a
valid URL does not make it safe to interpolate, so escape `name`, `category` and `docs_url` too, and
normalise the URL at write time as well.

## CI workflow

The job runs the generator, then Jekyll, then the deploy. Triggers:

- **`push`** filtered to the umbrella's own sources (`docs/**`, `scripts/**`, the workflow);
- **`schedule`** — a daily cron is what makes a _sibling's_ new opt-in appear, because its push
  happens in another repository;
- **`workflow_dispatch`** for a manual rebuild.

The build steps: checkout → Node (`node --test`, then the generator with the org token in
`GH_TOKEN`) → `ruby/setup-ruby@v1` (`bundler-cache`, `working-directory: docs`) →
`actions/configure-pages@v5` → `bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"`
→ `actions/upload-pages-artifact@v3` (`docs/_site`) → `actions/deploy-pages@v4`.

## Auth — an org-level token

Enumerating the org and reading its repositories needs a token the default workflow token cannot
provide (org repos are usually private). Create an **organisation-level Actions secret** (e.g.
`UMBRELLA_TOKEN`) holding a **fine-grained** PAT with:

- **Metadata: read** — for `GET /orgs/<org>/repos`;
- **Contents: read** — for the per-repo file reads;
- repository access = **All repositories** (so a newly created repo is discovered with no token edit);
- resource owner = **the organisation**, not a personal account.

No organisation-level permission is involved. Two footguns: a **classic** token never returns the
`X-Accepted-GitHub-Permissions` header that fine-grained tokens do, and a personal-account-owned
token cannot see the org's repos.

## One-off manual setup

Not expressible in the repo, so hand it to the user explicitly:

1. **Create (or rename to) the repository literally named `<org>.github.io`.**
2. **Create the organisation secret** the workflow reads (the fine-grained PAT above).
3. **Repository Settings → Pages → Source = "GitHub Actions".** The workflow cannot enable Pages
   itself; leaving it on "Deploy from a branch" makes `deploy-pages` fail — or worse, silently
   publishes the branch build instead (see Gotchas).

## Promoting a repository to the org root

Renaming a project repo to `<org>.github.io` is a **topology change**, and GitHub does not rebuild on
a rename:

- A rename is not a push, so a workflow gated on `on.push.paths` never fires and the previously
  deployed artifact keeps serving — built with the **old** base path.
- The symptom is a page with **content but no styling**: the HTML still points at
  `/<old-repo>/assets/css/site.css` while the files now sit at the site root. It misleads because
  `/assets/css/site.css` returns `200` while `/<old-repo>/assets/css/site.css` returns `404`.
- **Fix:** re-run the Pages workflow once (`gh workflow run <workflow>.yml --repo <org>/<repo>`) so
  `configure-pages` re-derives an empty `base_path`. The daily cron is the backstop.

The same rule applies to a **Pages source change**: deployment-configuration changes never redeploy on
their own. Trigger the workflow once after any of them.

## Gotchas

- **An org repo named anything other than `<org>.github.io` serves at `/<repo>/`.** Designing around
  "the org root" without that exact name produces a 404 at the root and a working site one path down.
- **A branch build silently overwrites the Actions deploy.** With Pages Source left on "Deploy from a
  branch", GitHub runs its own Jekyll build on every push and deploys _that_ — honouring only the
  repo's `_config.yml`, so an empty `baseurl` yields root-relative links and an unstyled site, while
  your workflow log shows a correct build. Diagnose with `gh api repos/<org>/<repo>/pages --jq .build_type`
  (`legacy` vs `workflow`).
- **A missing config is normal; a broken one is not silent.** 404 → skip quietly. Present but
  unreadable or invalid → `WARN:` + skip, exit 0. Never let one sibling's mistake fail the build.
- **Aggregation reads the remote default branch.** A sibling's config appears only once **pushed**;
  until the next scheduled run, a freshly pushed opt-in is simply not listed yet.
- **Liquid does not escape.** See [Rendering the index](#rendering-the-index) — escape every field.
- **Don't add a cross-repo asset fetch for "brand parity".** Each site carries its own committed copy
  of the logos; the aggregator is deliberately zero-dependency.

## Templates

Copyable scaffolds ship with this skill, genericised with `<org>` / `<repo>` / `<Project Name>`
placeholders — in prose, in config and in URIs. The one exception is the generator's default org
(`scripts/generate-projects.mjs`), which uses the literal `your-org` because a JavaScript string
cannot carry an angle-bracket placeholder:

- `assets/org-umbrella/` — the umbrella repo: `docs/` Jekyll site, `scripts/` generator + tests,
  `.github/workflows/umbrella-pages.yml`, `.gitignore`.
- `assets/project-site/` — one project's `docs/` Jekyll site plus its Pages workflow and the
  `umbrella-integration.json` opt-in.

## See also

- Stage 5 of `devbot:gh-pages` — the project-site scaffold the umbrella links to.
- `devbot:documentation-rules` — repository documentation conventions.
- [GitHub Pages documentation](https://docs.github.com/en/pages) — org vs project site hosting.
