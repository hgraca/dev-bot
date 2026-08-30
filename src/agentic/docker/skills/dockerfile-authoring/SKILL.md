---
name: devbot:dockerfile-authoring
description: Battle-tested patterns for writing, refactoring, reviewing, and debugging Dockerfiles. Use this whenever the user wants to create, edit, optimize, slim down, speed up, secure, or review a Dockerfile or container build — including multi-stage builds, layer/build caching, image-size reduction, installing dependencies or native extensions, pinning versions, build secrets, or diagnosing builds that are slow, stuck, bloated, or producing "output clipped" logs. Trigger even when the user only mentions a "Dockerfile", "docker build", "container image", or pastes a Dockerfile, without explicitly asking for best practices.
---

# Building, refactoring, and reviewing Dockerfiles

This skill captures patterns for production-grade Dockerfiles: small runtime images, fast cached builds, reproducible pins, and no secrets or build tooling leaking into the final image. Apply them when authoring from scratch, refactoring an existing Dockerfile, or reviewing one.

## Core mental model: build-time vs run-time

Almost every Dockerfile improvement comes from asking one question of every byte in the image: **is this needed to _run_ the app, or only to _build_ it?** Compilers, code generators, SDKs, dependency manifests, package caches, and credentials are build-time. The runtime needs only the app, its runtime libraries, and its installed dependencies. Anything build-time that ends up in the final image is wasted size, extra attack surface, or a leaked secret.

Multi-stage builds are the mechanism for enforcing that split: do the messy work in throwaway stages, then `COPY --from=...` only the finished artifacts into a lean final stage. Hold this question in mind through every pattern below.

## Workflow

1. **Start with `# syntax=docker/dockerfile:1`** as the first line — it enables BuildKit features (cache mounts, secret mounts, `COPY --from` of inline images).
2. **Pick the base image deliberately**: pin it (including the OS/distro suffix, and ideally the patch version), and prefer slim/runtime variants for the final stage.
3. **Identify the build-only work** (compiling extensions, generating code, installing dev dependencies, downloading tools) and plan a stage for each cluster of it.
4. **Lay out stages** so the final/default stage is lean and last. A common shape: `base` (shared runtime) → `deps`/`vendor` (cached dependencies) and `builder`/`codegen` (build tooling + generated artifacts) → `dev` and `production`.
5. **Order instructions within each stage** so the cheapest-to-invalidate things come last (copy source code near the end).
6. **Pin and verify** everything you download.
7. **Add a sanity check** (assert a tool resolves or prints its version) after non-obvious build steps.
8. **Review against the checklist** at the bottom before finishing.

For fuller code and a complete annotated multi-stage example, read `references/patterns.md`. To diagnose a build that's misbehaving (slow, stuck, bloated, truncated logs, or a failing `COPY --from`), read `references/troubleshooting.md`.

## The patterns

### 1. Use multi-stage builds to separate build from runtime

Define a lean `base`, do build work in derived stages, and have the final stage copy only artifacts. The final stage should never contain compilers or codegen tools that were only needed to produce those artifacts. Put the final (deployable) stage **last** so it is the default `docker build` target; build others with `--target <name>`.

### 2. Cache dependencies in a dedicated stage

Copy only the dependency manifest (and lockfile) first, install, then copy the result forward. A layer's cache is invalidated when its copied inputs change, so installing right after `COPY . .` re-runs the install on every source edit. Isolating it means dependencies reinstall only when the manifest changes — a huge CI win.

```dockerfile
FROM base AS deps
COPY package.json package-lock.json ./   # manifest only
RUN npm ci                                # cached unless the manifest changes
# ...in the final stage...
COPY --from=deps /app/node_modules node_modules/
```

The same shape applies to Composer (`composer.json`/`composer.lock` → `composer install`), pip (`requirements.txt`), Cargo, Go modules, etc.

### 3. Keep build-only tooling out of the final image

If you compile a native extension or run a code generator, put the toolchain (compilers, `cmake`, downloaded codegen binaries and plugins) in a **builder** stage, run the build there, and copy only the produced files into the final stage. Do **not** install that toolchain into a `base` that the production stage inherits — everything in `base` ships. This is the single biggest lever on final image size.

### 4. Order layers so the cheapest-to-invalidate change is last

Within a stage, install OS packages and build dependencies first (they rarely change), then `COPY` source code last (it changes constantly). Expensive steps — compiling a library, building a plugin — belong **before** any `COPY` of source so they stay cached across code edits.

### 5. Use package-manager cache mounts correctly

Cache mounts persist a package cache across builds without baking it into the image. Get all four details right (apt shown; adapt for apk/dnf/etc.):

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends <packages>
```

- `sharing=locked` prevents corruption from concurrent builds sharing the cache.
- `rm -f /etc/apt/apt.conf.d/docker-clean` lets the `/var/cache/apt` mount actually retain `.deb` files (Debian/Ubuntu base images auto-delete them otherwise, defeating the cache).
- **Do NOT** add `rm -rf /var/lib/apt/lists/*`. With a cache mount, that path isn't in the image layer anyway, so the `rm` only wipes the cache for the _next_ build — counterproductive.
- `--no-install-recommends` keeps the image lean.

### 6. Pin versions and verify integrity

Avoid `latest` and floating tags for anything affecting reproducibility or security. Pin the base image, OS packages, language dependencies, and downloaded binaries/installers. For anything fetched over the network, verify a checksum so a changed or compromised artifact fails the build loudly instead of silently shipping:

```dockerfile
ADD --chmod=0755 https://example.com/releases/download/2.11.12/tool /usr/local/bin/
RUN echo '<sha256>  /usr/local/bin/tool' | sha256sum -c -
```

Same idea for release archives: `wget` the pinned version, `sha256sum -c -`, then unzip.

### 7. Match build-tool versions to runtime versions

When a build tool generates code that a runtime library consumes (a code generator ↔ its runtime), or a plugin pairs with a library, their versions must be compatible. Pulling the build tool from the distro package manager often gives an _old_ version that mismatches a pinned runtime and breaks — at build time or, worse, subtly at runtime. Pin the build tool to match the runtime explicitly rather than trusting `apt`/`apk`.

> Session example: `protoc` and `grpc_php_plugin` had to match the pinned `protobuf`/`grpc` runtime extension versions. The distro's old `protoc` (3.12) rejected `proto3 optional` fields that the 3.22 runtime used, until it required an `--experimental_allow_proto3_optional` flag. Fetching the matching `protoc` (22.0) fixed it cleanly.

### 8. Parallelize native compiles — and watch memory

Long single-threaded compiles are a top cause of "stuck"-looking builds. Pass parallelism explicitly (`-j"$(nproc)"`, `MAKEFLAGS=-j"$(nproc)"`, or a tool's own flag — e.g. an installer that already parallelizes). But parallel native builds (gRPC is notorious) are memory-hungry; on a small machine, high parallelism trips the OOM killer, which presents as a silent hang. Cap cores (`-j4`, or a tool-specific limit) or raise the build memory if that happens. For source builds, shallow-clone to save time: `git clone --depth 1 -b <tag>` and `git submodule update --init --depth 1`.

### 9. Handle secrets without baking them in

A credential set as `ENV` (or even passed as `ARG`) in a stage persists in that image's layers/metadata. Use a **BuildKit secret mount** so it never lands in any layer:

```dockerfile
RUN --mount=type=secret,id=MY_SECRET \
    export MY_SECRET=$(cat /run/secrets/MY_SECRET) && \
    install-private-deps
```

When using `docker/build-push-action` in GitHub Actions, pass secrets via the `secrets` input:

```yaml
- uses: docker/build-push-action@v7
  with:
    secrets: |
      "MY_SECRET=${{ secrets.MY_SECRET }}"
```

**`.npmrc` + secret mount for private registries:** When `.npmrc` uses env var substitution (e.g., `//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}`), mount the token as a secret and export it:

```dockerfile
RUN --mount=type=secret,id=NODE_AUTH_TOKEN \
    export NODE_AUTH_TOKEN=$(cat /run/secrets/NODE_AUTH_TOKEN) && \
    yarn install
```

The exported env var is available to the `RUN` step only — it never appears in `docker history` or image layers.

### 10. Keep WORKDIR consistent across stages

A child stage inherits its parent's `WORKDIR`, but a stage built directly `FROM <image>` uses that image's default (e.g., the official `php:*-fpm` images default to `/var/www/html`, not `/`). If one stage installs to `/app` while another does `COPY --from=that /app/...` but the source stage actually wrote to a different default dir, the build fails with a "not found". Set `WORKDIR` once in `base` so derived stages share it, and re-check the path in every `COPY --from`.

### 11. Add sanity checks after non-obvious steps

A cheap assertion turns a silent misconfiguration into a clear failure at the right line:

```dockerfile
RUN tool --version && command -v other-tool
```

Don't run a binary that reads stdin (e.g., a protoc plugin) with `--version` if it might block — prefer `command -v` to just confirm it's on `PATH`.

### 12. Differentiate dev and prod targets

Dev images carry debuggers, test tooling, and a development config; production stays lean. Use sibling stages from a shared `base`, select with `--target`, and put the production stage last (the default). Use the development config in dev and the production config in prod — don't let a dev image silently inherit production settings (e.g., copy `php.ini-development` in dev, `php.ini-production` in prod). Run app build steps (route/view/config caches, asset builds) in the stage that ships them, after the code and dependencies are in place — and be aware that installing dependencies with a "skip scripts" flag in a deps stage means framework post-install hooks (e.g., package discovery) didn't run there.

## Review checklist

Before finishing or when reviewing, verify:

- Final/default stage contains no compilers, codegen tools, SDKs, or dependency manifests it doesn't need at runtime.
- No secret is set as `ENV`/`ARG` in a stage that ships.
- Dependencies install from a manifest-only copy, not after `COPY . .`.
- Base image and downloaded artifacts are pinned and checksum-verified; no `latest`.
- Every `COPY --from=<stage> <src>` path actually exists in the source stage (WORKDIR sanity).
- Package installs use cache mounts with `sharing=locked`, drop `docker-clean`, do NOT `rm` the cached lists dir, and use `--no-install-recommends`.
- Expensive/stable steps sit before the source `COPY`; the source copy is near the end.
- Native compiles are parallelized, with an OOM escape hatch noted.
- Build tools that generate code are version-matched to the runtime libraries that consume it.
- `# syntax=docker/dockerfile:1` is the first line.

## References

- `references/patterns.md` — fuller code for each pattern plus a complete annotated multi-stage Dockerfile.
- `references/troubleshooting.md` — diagnosing slow, stuck, bloated, or log-truncated builds, and common multi-stage bugs.
