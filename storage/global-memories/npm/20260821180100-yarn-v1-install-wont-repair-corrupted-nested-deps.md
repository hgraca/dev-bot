---
date: 2026-08-21
keywords: ['npm', 'yarn', 'node_modules', 'babel', 'jest']
trigger-on: ['yarn-install', 'broken-node-modules', 'jest-cannot-find-module']
---

## yarn v1 `install` won't repair a corrupted nested dependency — do a clean reinstall

yarn v1 only adds/fetches what the lockfile demands; it does not prune or rebuild extraneous broken directories left inside `node_modules`. Symptom seen in driver-service (2026-08-21): jest failed on every suite with `Cannot find module '@babel/helper-split-export-declaration'` required from a stale nested copy at `node_modules/@babel/core/node_modules/@babel/traverse/...` — repeated `yarn install` runs (including after dependency bumps) did not fix it. The fix that worked: `rm -rf node_modules && yarn install`. When jest/ts-jest fails at module load with a missing transitive babel module, suspect this before debugging your own code; the same stale-`node_modules` class of issue also shows up as TS version drift after lockfile bumps in Docker-mount setups.
