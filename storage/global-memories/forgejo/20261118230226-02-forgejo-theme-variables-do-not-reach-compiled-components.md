---
date: 2026-11-18
keywords: ["forgejo", "theme", "css-variables", "fomantic", "chroma"]
---

## Forgejo theming: the variables cover the chrome, not the compiled components

Forgejo paints through `--color-*` custom properties declared in `assets/css/theme-forgejo-<theme>.css`, so overriding those properties repoints surfaces, text, links and borders from one stylesheet per variant. Three things sit outside that contract: Fomantic components are compiled with the framework's own palette (`.ui.primary.button` stays Fomantic blue, not `--color-primary`), Chroma and CodeMirror token colours live in the theme file keyed to `prefers-color-scheme`, and light/dark markup images follow the OS through the same media query. A theme driven by an explicit user choice (cookie or attribute) must override those three explicitly, or syntax highlighting and the buttons will disagree with the chosen mode. The `custom/header` template hook renders at the end of `<head>`, after Forgejo's own stylesheets, so linking the override there wins the cascade without `!important`; restricting `[ui] THEMES` and `DEFAULT_THEME` keeps the now-inert theme picker off the settings page.
