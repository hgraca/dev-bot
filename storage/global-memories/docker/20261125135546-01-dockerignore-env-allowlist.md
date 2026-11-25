---
date: 2026-11-25
keywords: ["docker", "dockerignore", "env-file", "build-context"]
aliases: ["dev env baked into image", "dotenv in image layer", ".dockerignore allowlist"]
trigger-on: ["docker-build-context", "dockerignore-env"]
---

## Exclude local env files from Docker build contexts with an allowlist

A `COPY . .` build bakes the developer's `.env` into an image layer even when the entrypoint later replaces it, and the original stays readable from the image. In `.dockerignore` use `.env` plus `.env.*` and then `!.env.production` / `!.env.staging` — the negations must follow the wildcard — so the deploy env files the entrypoint moves into place stay in the context. Exclude local-only directories the build never needs (`no-vcs/`, `.agents/`, `graphify-out/`, `docs/`), but keep application code such as a PSR-4 `lib/` overlay. Verify with a throwaway build: `printf 'FROM alpine:3.20\nCOPY . /ctx\nRUN test ! -e /ctx/.env && test -e /ctx/.env.production\n' | docker build -f - .`.
