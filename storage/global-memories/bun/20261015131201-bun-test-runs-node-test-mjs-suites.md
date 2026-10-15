---
date: 2026-10-15
keywords: ["bun", "bun test", "node:test", "test discovery", "mjs"]
aliases: ["node:test under bun", "bun does not discover .test.mjs", "bun test file discovery"]
trigger-on: ["bun-test-discovery", "shipping-node-test-suites"]
---

## `bun test` discovers `.test.mjs` and runs `node:test` suites under its own runner

`bun test <dir>` picks up `.test.mjs` files, not only `.js`/`.ts` — and a suite written for Node's built-in runner (`import { test } from "node:test"; import assert from "node:assert/strict"`) executes green under it with no shim or config (verified on bun 1.3.13: a 35-test `node:test` suite written for `node --test` passed unchanged under `bun test`). Consequence when a repo's gate is `bun test src/`: any `.test.mjs` anywhere under `src/` — including test files shipped inside a copied scaffold or template directory — joins the suite automatically, and bun only prints a per-file header for files that FAIL, so a passing template suite is invisible in the output and its test count has to be read from the run summary. Shipping a template's tests is therefore safe and earns them the same coverage as first-party code, but a template whose tests do not pass standalone will break the repo's gate. Before committing such files, run `bun test <that dir>` to confirm they pass with nothing else in the run.
