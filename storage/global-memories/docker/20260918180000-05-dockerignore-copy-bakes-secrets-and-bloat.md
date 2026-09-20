---
date: 2026-09-18
keywords: ["docker", "dockerignore", "build-context", "secrets"]
trigger-on: ["dockerfile-copy", "dockerignore", "docker-build"]
---

## Without a .dockerignore, `COPY . .` bakes local secrets and hundreds of MB into the image

A Dockerfile that copies the build context wholesale ships whatever is in the working tree, including gitignored files — so a developer's `.env` (with real credentials) ends up inside the image, alongside `.git`, agent state and any large generated output directory. This is invisible in CI because gitignored paths are absent from a fresh checkout, so it only bites local builds, which is precisely how credentials get pushed to a registry by hand. Always add a `.dockerignore` covering at least `.git/`, `.env*`, `vendor/`, `node_modules/`, tests, editor directories and build-output folders. Note the Dockerfile itself is read separately from the context, so excluding `*.Dockerfile` is safe under BuildKit.
