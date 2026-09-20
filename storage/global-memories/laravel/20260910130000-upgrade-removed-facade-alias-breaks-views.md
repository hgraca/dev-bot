---
date: 2026-09-10
keywords: ["laravel", "upgrade", "facade", "blade", "laravelcollective"]
trigger-on: ["laravel-major-upgrade-removed-package", "facade-alias-removed"]
---

## Removing a facade alias in a Laravel major upgrade breaks views that still use it

When a major Laravel upgrade drops a package that registered a facade alias (e.g. `laravelcollective/html`'s `Form`/`Html`), the alias disappears from `config/app.php` — but any Blade view still calling `Form::open()` keeps compiling fine and only fails at render time with `Class "Form" not found` (a `ViewException` → HTTP 500). Blade templates are compiled lazily and are not covered by PHPStan/lint, so a static sweep will not catch them. After such an upgrade, grep the whole repo for the removed alias (`grep -rn "Form::\|Html::" resources/views/`) and confirm the package is really gone (`vendor/<vendor>` absent, no composer entry). A missed view can stay broken silently until someone hits the route.
