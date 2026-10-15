---
date: 2026-10-13
keywords: ["jekyll", "relative_url", "baseurl", "github-pages"]
aliases: ["docs link 404 under project page", "baseurl not applied to markdown link"]
trigger-on: ["jekyll-site", "github-pages-baseurl"]
---

## `relative_url` is a Liquid filter — root-relative links in markdown prose still 404 under a project base path

A Jekyll site built with `--baseurl /<repo>` (what `configure-pages` + `--baseurl "${{ steps.pages.outputs.base_path }}"` does for a GitHub Pages project site) prefixes URLs only where the Liquid filter is actually applied. A markdown link written as `[Storybook](/storybook/)` is emitted verbatim by kramdown as `href="/storybook/"`, which on `https://<org>.github.io/<repo>/` resolves to the domain root and 404s.

Layouts, includes and pages that already use `{{ '/storybook/' | relative_url }}` are fine — the gap is prose. Fix: apply the filter inside the markdown link destination too, `[Storybook]({{ '/storybook/' | relative_url }})` (kramdown runs after Liquid, so inline Liquid in a `.md` works). Verify against a base-path build, not a local one: build with `--baseurl /<repo>` and grep the output for `href="/(storybook|components)/"` — the local build with an empty baseurl renders identical-looking links and hides the bug.
