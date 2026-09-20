---
date: 2026-09-15
keywords: ["shell", "makefile", "docker", "ci", "composer"]
trigger-on: ["gete-devtools-makefile", "make-ci-targets"]
---

## get-e/dev-tools `ci-*` make targets only work in-place, and clobber the local env when run locally

The DevTools makefiles split targets in two ways. User-facing targets (`unit`, `ut`, `test`, `static`, …) wrap into the container through `.docker-wrap-%`, so they work from the host. The `ci-*` targets (`ci-unit`, `ci-unit-coverage`, `ci-test-static_analysis`) instead call the hidden recipes directly — `ci-test-static_analysis` runs `$(MAKE) .install-deps`, which executes `composer install` in the *current* shell. In CI that is fine (the runner has PHP and composer on PATH and each workflow prepares its own env first); on a developer host, `make ci-test-static_analysis` dies with `composer: command not found` / `Error 127`, which looks like a broken repo but is not. Run it inside the app container instead: `docker exec -i --workdir /app --user "$(id -u):$(id -g)" <project>-app-1 make ci-test-static_analysis`. The same recipes are also destructive when run locally — `ci-unit`/`ci-unit-coverage` append `.env.phpunit.ci` to `.env.phpunit` and overwrite `.env` with it, pointing `DB_HOST` at 127.0.0.1 instead of the container's `db` — so use the wrapped `unit`/`ut` targets for local runs. Note a project's `Makefile.proj.mk` can also drift from the vendored template and be missing hidden targets entirely (e.g. `.ut`), which makes the documented command fall through to `.DEFAULT` and print "Command '.ut' not found."
