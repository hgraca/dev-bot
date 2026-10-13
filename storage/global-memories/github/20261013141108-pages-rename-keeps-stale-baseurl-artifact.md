---
date: 2026-10-13
keywords: ["github", "github-pages", "rename", "baseurl", "stale-artifact"]
trigger-on: ["github-pages-repo-rename", "pages-serving-path-change", "site-unstyled-after-rename"]
---

## Renaming a repo never triggers a Pages rebuild — the old artifact keeps its previous baseurl prefix

Renaming a repository (e.g. `get-e` → `get-e.github.io` so it becomes the org-root site) does not itself trigger a Pages deployment: a rename is not a push, so a workflow gated on `on.push.paths` never matches and the previously deployed artifact keeps serving. That artifact was built with the *old* base path, so its HTML still references `/get-e/assets/css/site.css` while its own files now sit at the site root — the prefixed link 404s and the page renders with **content but no styling**. The signature misleads because the internal paths are still valid: `curl -sI https://<org>.github.io/assets/css/site.css` returns 200 while `.../get-e/assets/css/site.css` returns 404. Diagnose by comparing the live HTML's asset URLs against the site's real root, then fix by re-running the Pages workflow once (`gh workflow run <wf>.yml --repo <org>/<repo>`) so `actions/configure-pages` re-derives an empty `base_path` for an org-root site; the site's daily cron is the backstop. The same holds for a Pages *source* change — deployment-configuration changes never redeploy on their own.
