---
name: devbot:gh-docs-website
description: "Use this skill whenever the user wants to create, build, or publish a documentation website for a project — a static docs site on GitHub Pages generated with Jekyll — even if they don't say 'documentation' or 'Jekyll' explicitly (e.g. 'make a docs site', 'put our docs online', 'publish the README as a website', 'docs website', 'gh-pages', 'github pages'). Guides the full flow end to end: understand the target audience, gather project information, scope the documentation, write the content, then set up the technical artifacts (Jekyll site structure, _config.yml, layouts/includes, GitHub Actions deployment workflow). Use it for both the content strategy and the technical implementation."
---

# gh-docs-website

Guide an agent through building a documentation static website for a project, hosted on GitHub Pages and generated with Jekyll. The skill covers the full flow end to end — from deciding who the docs are for, to writing the content, to wiring up the build and deployment.

This is a **process skill**, not a generator. Work through the stages in order, in small increments, and check in with the user at each stage boundary before proceeding. Do not scaffold files until the audience, scope, and information-gathering stages are done.

## Stages

```
1. UNDERSTAND AUDIENCE ─► 2. GATHER INFO ─► 3. SCOPE ─► 4. WRITE ─► 5. SET UP ARTIFACTS
```

Each stage produces a concrete output that the next stage depends on. Confirm with the user before moving on.

---

## Stage 1 — Understand the target audience

Before writing a single line of documentation, establish **who** the site is for. Every later decision (tone, depth, structure, examples) derives from this.

Ask the user, one question at a time, until you can answer all of the following:

- **Who reads this?** (e.g. end users, new contributors, maintainers, power users, integrators, a mix)
- **What is their primary goal when they land on the site?** (get started, understand concepts, find a reference, contribute, troubleshoot)
- **What is their assumed prior knowledge?** (novice, familiar with the domain, expert)
- **What does a successful visit look like?** (they install it, they submit a PR, they answer their own question)

Classify the audience explicitly. Common archetypes and how they shape the site:

| Audience         | Focus                                                | Tone / depth                             |
| ---------------- | ---------------------------------------------------- | ---------------------------------------- |
| **End users**    | Quick start, install, features, troubleshooting      | Concrete, task-oriented, minimal jargon  |
| **Contributors** | Setup, architecture, conventions, contribution guide | Technical, links to code, "how it works" |
| **Maintainers**  | Architecture, module/reference docs, decisions       | Dense reference, cross-linked            |
| **Integrators**  | API surface, configuration, extension points         | Contract-focused, code examples, schemas |

Record the outcome as a short **audience statement** (2–4 sentences) and show it to the user. Do not proceed until the audience is agreed.

---

## Stage 2 — Gather information about the project

Collect the material the documentation will be built from. Ground the docs in the _actual_ project, not assumptions.

Gather from these sources, in this order:

1. **README** — the project's own framing: what it is, why it exists, quick start.
2. **Directory structure** — the top-level layout (source layout, entry points, config files, tests). Use `tree` / glob tools, not assumptions.
3. **Entry points & CLI** — how users actually invoke the project (commands, flags, subcommands, `--help` output).
4. **Configuration surface** — config files, environment variables, and their meaning. Read the defaults/dist files.
5. **Public API / extension points** — interfaces, exported functions, plugins, hooks.
6. **Existing documentation** — any `.md` docs, comments, ADRs, or wiki content that can be reused or referenced.
7. **Project metadata** — license, repository URL, versioning/release process, support channels.

Rules while gathering:

- **Verify against the code.** Do not document behaviour you have not read. If a claim is unverifiable, mark it for the user to confirm.
- **Record, don't editorialize yet.** Stage 2 output is a neutral inventory of facts and links to source locations, not prose.
- **Note gaps.** Anything the audience (Stage 1) would need that is not yet documented is the raw material for Stage 3.

Output: a short **information inventory** (what exists, where it lives, what is missing). Confirm with the user that the inventory matches their understanding of the project.

---

## Stage 3 — Ask about documentation scope

The audience statement and the information inventory now let you scope what to actually write. Ask the user to bound the effort.

Questions to ask:

- **Which sections should exist?** Propose a candidate sitemap based on the audience (Stage 1) and inventory (Stage 2); let the user add, remove, or reorder.
- **How deep?** Overview pages only, or per-topic reference pages too?
- **What must ship now vs later?** Prioritize; suggest deferring low-value pages.
- **Single page or multi-page?** A one-pager is legitimate for small projects; a sectioned site scales better.
- **Any content to exclude or avoid?** (internal notes, pre-release features, secrets, unreleased APIs)
- **Who owns maintenance?** Will docs be updated with code changes, or is this a one-off?

Produce a **sitemap** — an ordered list of pages with a one-line description of each — plus a note of what is explicitly out of scope. Confirm before writing.

A typical sitemap for a developer-tool project:

```
index.md              Landing / hero + quick start
get-started.md        Installation and first run
concepts.md           Core concepts (optional)
configuration.md      Config reference
<topic>/index.md      Section index
<topic>/<page>.md     Per-topic reference pages
```

---

## Stage 4 — Write the documentation

Write the content page by page, following the agreed sitemap. Keep each page focused on one job.

Writing rules:

- **Lead with the reader's goal.** Open each page with what the reader came to do, not with marketing.
- **One page, one purpose.** Split reference material from narrative. Cross-link instead of duplicating.
- **Frontmatter on every page.** Each markdown page needs at minimum a `title`, a `description`, and the intended `layout` (see Stage 5).
- **Use relative links** (`/section/page`) so the site works under a `baseurl` subpath (e.g. GitHub Pages project sites at `https://<org>.github.io/<repo>/`).
- **Prefer tables for reference data** (options, commands, endpoints); prose for concepts and tasks.
- **Verify code samples** are accurate against the project; prefer real, minimal examples over pseudo-code.
- **No project-internal-only details.** The site is public — exclude secrets, internal URLs, and unreleased features unless the user confirms otherwise.

Work incrementally: write one page, show it to the user, and only move on after it reads correctly. Do not dump the entire site in one pass.

---

## Stage 5 — Set up the technical artifacts

Scaffold the Jekyll site and the GitHub Pages deployment. Only start this stage once the content exists (Stages 1–4); the scaffold is a thin shell around the content, not the work itself.

### 5.1 Directory layout

A `docs/` directory at the repository root, treated as the Jekyll site root:

```
docs/
├── _config.yml          # Jekyll site configuration
├── Gemfile              # Ruby dependencies (jekyll, seo plugin, webrick)
├── Gemfile.lock         # Locked dependency versions (committed)
├── .bundle/config       # Pin bundler to docs/vendor/bundle
├── _layouts/
│   ├── default.html     # Base shell: <head>, nav, main, footer
│   ├── home.html        # Landing-page layout
│   └── page.html        # Content-page layout
├── _includes/
│   ├── nav.html         # Header / navigation
│   └── footer.html      # Footer
├── assets/css/style.css # Site styling
├── imgs/icons/          # Favicon + icons in multiple sizes
├── index.md             # Home page
└── <section>.md         # Content pages
```

### 5.2 `_config.yml`

The minimal, working configuration:

```yaml
title: <Project Name>
description: >-
    <One-sentence description>
url: "https://<org>.github.io"
baseurl: "/<repo>"

markdown: kramdown
highlighter: rouge

kramdown:
    input: GFM
    syntax_highlighter: rouge

plugins:
    - jekyll-seo-tag

defaults:
    - scope:
          path: ""
          type: "pages"
      values:
          layout: "page"

exclude:
    - Gemfile
    - Gemfile.lock
    - vendor
    - .bundle

permalink: pretty
```

Key points:

- **`baseurl`** — the repo name; required for project sites (not `user.github.io` user sites).
- **`exclude`** — keep bundler/vendor files out of the generated site.
- **`permalink: pretty`** — clean URLs (`/page/` instead of `/page.html`).

### 5.3 `Gemfile` and bundler config

```ruby
source "https://rubygems.org"

gem "jekyll", "~> 4.3"
gem "jekyll-seo-tag", "~> 2.8"
gem "webrick", "~> 1.8"
```

`docs/.bundle/config`:

```
---
BUNDLE_PATH: "vendor/bundle"
```

Generate `Gemfile.lock` locally with `bundle install` and commit it — the CI build relies on the lock file for reproducibility.

### 5.4 Layouts and includes

- **`_layouts/default.html`** — the single base shell. Holds the `<head>` (charset, viewport, `<title>`, meta description, `{% seo %}`, favicon links, stylesheet), includes `nav.html`, renders `{{ content }}`, includes `footer.html`. Keep site-wide scripts (mobile nav, optional diagram rendering) here.
- **`_layouts/home.html`** — thin wrapper (`layout: default` + `{{ content }}`) so the landing page can use custom section markup while still sharing the shell.
- **`_layouts/page.html`** — the article shell: page title, optional description, then `{{ content }}` inside a `.prose` container.
- **`_includes/nav.html`** — the header: logo + primary nav links, active-state highlighting via `page.url` comparison, and a mobile toggle. Supports dropdown menus with a `nav_section` frontmatter field.
- **`_includes/footer.html`** — footer with brand, link columns, and copyright.

Use Jekyll filters `relative_url` / `absolute_url` for asset and link URLs so they respect `baseurl`.

### 5.5 Deployment workflow (GitHub Actions)

Add `.github/workflows/jekyll-gh-pages.yml` with a build + deploy job:

```yaml
name: Deploy Jekyll site to GitHub Pages

on:
    push:
        branches: ["main"]
        paths:
            - "docs/**"
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
            - name: Checkout
              uses: actions/checkout@v4

            - name: Setup Ruby
              uses: ruby/setup-ruby@v1
              with:
                  ruby-version: "3.3"
                  bundler-cache: true
                  working-directory: docs

            - name: Setup Pages
              id: pages
              uses: actions/configure-pages@v5

            - name: Build with Jekyll
              run: bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"
              working-directory: docs
              env:
                  JEKYLL_ENV: production

            - name: Upload artifact
              uses: actions/upload-pages-artifact@v3
              with:
                  path: docs/_site

    deploy:
        environment:
            name: github-pages
            url: ${{ steps.deployment.outputs.page_url }}
        runs-on: ubuntu-latest
        needs: build
        steps:
            - name: Deploy to GitHub Pages
              id: deployment
              uses: actions/deploy-pages@v4
```

Notes:

- The `paths` filter limits rebuilds to documentation changes only.
- `working-directory: docs` keeps Ruby/Jekyll scoped to the site root.
- The `build` job uses `steps.pages.outputs.base_path` so it works for both user and project sites.

### 5.6 Git and tooling hygiene

- **`.gitignore`** — add `docs/_site/`, `docs/.jekyll-cache/`, and `docs/vendor/` so generated output and bundler gems are never committed.
- **Local preview** — provide a `make docs` target (or equivalent) that runs `bundle install && bundle exec jekyll serve` inside `docs/`, so contributors can preview locally.
- **Verify before finishing** — run the build locally (`bundle exec jekyll build`) and confirm it succeeds with no warnings; check the generated `_site/` output. Confirm the site renders under the configured `baseurl`.

### 5.7 Completion checklist

- [ ] Audience statement agreed (Stage 1)
- [ ] Information inventory grounded in the code (Stage 2)
- [ ] Sitemap and scope agreed (Stage 3)
- [ ] All pages written with frontmatter and relative links (Stage 4)
- [ ] `docs/` scaffold in place (config, Gemfile, layouts, includes, assets)
- [ ] `.github/workflows/jekyll-gh-pages.yml` added
- [ ] `.gitignore` excludes `_site`, `.jekyll-cache`, `vendor`
- [ ] Local build passes cleanly
- [ ] GitHub Pages source set to GitHub Actions (noted for the user to enable in repo settings)

---

## Gotchas

Non-obvious mistakes that break a Jekyll + GitHub Pages site if the agent relies on generic knowledge:

- **`webrick` must be in the `Gemfile`.** Ruby 3.x no longer bundles webrick, so `bundle exec jekyll serve` fails locally without it even though the GitHub Actions build may still succeed.
- **`baseurl` is `/repo`, and forgetting it silently breaks everything.** GitHub Pages project sites are served from `https://<org>.github.io/<repo>/`, not the domain root. Missing or wrong `baseurl` produces 404s for every asset and link. Use `relative_url` / `absolute_url` filters instead of hard-coded `/` paths so links respect `baseurl`.
- **`{% seo %}` needs `title` and `description`.** The `jekyll-seo-tag` plugin emits nothing (or incomplete meta tags) when these are missing from `_config.yml` or the page frontmatter.
- **`kramdown` input must be `GFM`.** Without `input: GFM`, GitHub-flavored markdown (pipe tables, strikethrough, task lists) renders incorrectly.
- **Commit `Gemfile.lock`.** The `ruby/setup-ruby` action's `bundler-cache` relies on the lock file; without it the build is non-reproducible and can silently pick newer gem versions.
- **Exclude bundler files from the build.** Add `Gemfile`, `Gemfile.lock`, `vendor`, and `.bundle` to `_config.yml`'s `exclude`, or they leak into the generated `_site/`.
- **Gitignore the generated output.** `docs/_site/`, `docs/.jekyll-cache/`, and `docs/vendor/` must be ignored or the first commit accidentally stages build output.
- **The workflow's `paths` filter means non-docs edits don't redeploy.** If a user expects a redeploy after editing the root README or Makefile, the site won't rebuild unless `docs/**` or the workflow file itself changed.
- **Don't fight the platform with custom CI.** Use the official `configure-pages`/`upload-pages-artifact`/`deploy-pages` actions and pass `steps.pages.outputs.base_path` to the build; hand-rolling `gh-pages` branch pushes conflicts with the Pages token flow.

---

## Related Skills

- `documentation-and-adrs` — recording decisions and documentation conventions
- `devbot:documentation-rules` — repository documentation file organization conventions
- `devbot:format-md` — markdown formatting for consistency
- `shipping-and-launch` — pre-launch checklist and rollout
