---
date: 2026-11-27
keywords: ["pnpm", "ignored-builds", "lockfile-drift", "corepack"]
trigger-on: ["pnpm-version-drift", "pnpm-ignored-builds", "pnpm-lockfile-churn"]
---

## A newer local pnpm hard-fails where CI's older one only warns

`GET-E/portal` pins pnpm 10 in CI (`pnpm/action-setup`) while the developer machine had pnpm 11.9.0. pnpm 11 turns ignored build scripts into a **hard error**: every `pnpm <script>` aborted with `ERR_PNPM_IGNORED_BUILDS: Ignored build scripts: cypress, esbuild, @mui/x-telemetry` because `package.json`'s `pnpm.onlyBuiltDependencies` is deprecated in 11 (it says so: "The pnpm field in package.json is no longer read"), so neither Cypress nor esbuild's postinstall ran and Vite could not start. pnpm 10.34 reads the field and only warns. Two further traps: (a) pnpm 10 refuses to delete a `node_modules` built by another major without confirmation — `ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY` — so a scripted reinstall needs `CI=true` in the environment; (b) mixing pnpm majors across one lockfile re-resolves the peer graph wholesale, which shows up as ~1300 lines of churn where `(supports-color@10.2.2)` peer suffixes vanish from every importer, and `--frozen-lockfile` does not catch it because it only validates importers. The fix is to declare `"packageManager": "pnpm@10.34.9"` (corepack honours it) and let `pnpm/action-setup` read it instead of repeating `version: 10` — one producer for one lockfile. Run project commands through that pinned version (`npx --yes pnpm@10 …`) when comparing against CI behaviour.
