# Troubleshooting builds

A symptom-first guide to the build problems behind the patterns in `SKILL.md`. Find the symptom, apply the fix.

## Logs stop mid-build: "output clipped, log limit ... reached"

**This is not a failure.** BuildKit caps how much log a single step may emit (default ~2 MiB, ~200 KiB/s); once a step exceeds that, the remaining output is hidden and you see the "output clipped" line. The build keeps running. It usually appears on a long, verbose step (a big native compile), so the real issue is often slowness (below), not the clipping.

To see the full logs, raise or disable the limit. The variables are `BUILDKIT_STEP_LOG_MAX_SIZE` and `BUILDKIT_STEP_LOG_MAX_SPEED`; `-1` disables each. These are read by the BuildKit daemon, not the CLI, so a shell var in front of `docker build` won't reliably take. Set them where BuildKit runs:

- **Default `docker` driver (Linux, systemd dockerd):** add to the docker service unit
  `Environment="BUILDKIT_STEP_LOG_MAX_SIZE=-1"` and `Environment="BUILDKIT_STEP_LOG_MAX_SPEED=-1"`,
  then `systemctl daemon-reload && systemctl restart docker`.
- **`docker-container` driver / Docker Desktop / any setup:** bake them into a dedicated builder:
    ```
    docker buildx create --use --name biglogs \
      --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
      --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1
    ```

Also pass `--progress=plain` for continuous, non-collapsed output.

## Build is very slow or appears to hang on a compile step

Most often a **single-threaded native compile**. Parallelize it:

- `make`: `make -j"$(nproc)"` or export `MAKEFLAGS="-j$(nproc)"` before the build.
- PECL specifically isn't parallel by default — set `MAKEFLAGS` or use a wrapper installer that parallelizes and auto-enables (e.g. `install-php-extensions`) instead of bare `pecl install`.
- Many ecosystem installers have their own job flag — pass it.

For source builds, also shallow-clone to cut fetch time: `git clone --depth 1 -b <tag>` and `git submodule update --init --depth 1`.

## Build dies silently part-way through a heavy compile (OOM)

Parallel native builds (gRPC, large C++ projects) are memory-hungry, and `-j"$(nproc)"` multiplies peak memory. On a constrained machine the OOM killer terminates the compiler, which looks like a silent hang or an opaque failure. Fixes:

- Cap parallelism: `make -j4`, or a tool-specific limit (e.g. `IPE_PROCESSOR_COUNT=4` for `install-php-extensions`).
- Raise the builder's memory (Docker Desktop: Settings → Resources).

## `COPY --from=<stage> <path>` fails with "not found"

The source stage never created that path. Usual cause: a **WORKDIR mismatch**. A stage built `FROM <image>` uses that image's default working directory (e.g. official `php:*-fpm` → `/var/www/html`), not `/app`. So a `deps`/`vendor` stage that copies its manifest to `./` writes to the image default, and a later `COPY --from=vendor /app/vendor` finds nothing.

Fix: set `WORKDIR /app` once in `base` so every derived stage inherits it, and confirm each `COPY --from` path matches where the source stage actually wrote.

## Codegen fails with a version/feature error (e.g. "experimental flag not set")

A **build tool / runtime version mismatch**. The generator is older than the runtime library that consumes its output, so it rejects newer syntax or emits incompatible code. Classic case: a distro-provided `protoc` (3.12) refusing `proto3 optional` fields that the pinned 3.22 runtime uses, demanding `--experimental_allow_proto3_optional`.

Don't paper over it with the experimental flag. Fetch the generator version that matches the runtime (here, `protoc` 22.0), pin it, and verify its checksum. The same applies to language-specific plugins (build them from the matching library tag).

## Final image is far larger than expected

Build-only weight leaked into the runtime image. Check for: compilers / `cmake` / build-essential, downloaded SDKs or codegen binaries, dependency caches, or `node_modules`/dev dependencies present only for a build step. Move that work into a builder stage and `COPY --from` only the artifacts into the final stage (see `references/patterns.md` §3). Also confirm the final stage uses a slim/runtime base variant, not a build/SDK image.

## Dependencies reinstall on every build

The install runs after `COPY . .`, so any source change invalidates it. Move the install into a stage that copies only the manifest + lockfile first, then `COPY --from` the installed dependencies into the final stage (`SKILL.md` pattern 2).

## A credential ended up in the shipped image

A token was set as `ENV` (or passed as `ARG`) in a stage that ships. Move it to a throwaway build stage the final image doesn't inherit, or use a secret mount (`--mount=type=secret`) so it never lands in a layer (`references/patterns.md` §7). Rebuild — old layers may still carry it, so don't just reuse the cached image.

## Cache mount seems to do nothing

Two common causes: (1) the base image's `docker-clean` config deletes downloaded packages before the next build can reuse them — `rm -f /etc/apt/apt.conf.d/docker-clean` inside the cache-mounted `RUN`; (2) a trailing `rm -rf /var/lib/apt/lists/*` (or `/var/cache/apt/*`) wipes the very directory the cache mount backs — remove it, since cache-mounted paths aren't part of the image layer anyway.
