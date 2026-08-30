# Patterns — fuller code and a complete example

This file expands the patterns in `SKILL.md` with more complete snippets, then ends with a full annotated multi-stage Dockerfile that combines them. The examples use a PHP-FPM / Laravel app with a native extension and a code-generation step, but the structure is language-agnostic — substitute your own runtime, package manager, and build tool.

## Table of contents

1. Stage layout and the default target
2. Dependency-caching stage
3. Builder stage that keeps tooling out of the runtime image
4. Correct package-manager cache mounts
5. Pinned + checksum-verified downloads
6. Architecture-aware downloads
7. Secret mounts
8. A complete annotated Dockerfile

---

## 1. Stage layout and the default target

A reliable shape is a shared lean `base`, derived stages for cached dependencies and for build tooling, and sibling `dev`/`production` leaves:

```
base ─┬─ deps      (cached dependencies)
      ├─ builder   (toolchain + generated artifacts)
      ├─ dev       (debug/test tooling; FROM base or FROM builder)
      └─ production (FROM base; copies artifacts from deps + builder)   ← last = default
```

The last stage in the file is what `docker build .` produces. Build a non-default stage with `docker build --target dev .`. BuildKit only builds stages in the dependency graph of the chosen target, so building `production` skips `dev` entirely.

## 2. Dependency-caching stage

Copy the manifest first so the install layer caches independently of source code:

```dockerfile
FROM base AS vendor
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./
COPY .patches/ .patches/
RUN --mount=type=secret,id=COMPOSER_AUTH \
    export COMPOSER_AUTH=$(cat /run/secrets/COMPOSER_AUTH) && \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader
```

Then in the final stage:

```dockerfile
COPY --from=vendor /app/vendor vendor/
```

Scope any registry/auth credential to this throwaway stage (see §7) so it never ships. Note the `--no-scripts`: it makes the install reproducible and code-independent, but framework post-install hooks (e.g. Laravel's `package:discover`) won't run here — run them later in the shipping stage if you depend on their output.

## 3. Builder stage that keeps tooling out of the runtime image

The toolchain (compilers, `cmake`, downloaded generators) goes in a stage that the final image does NOT inherit. Run the generation there; copy only the result:

```dockerfile
# Toolchain: build-only, never inherited by production.
FROM base AS toolchain
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends wget cmake
# ... download protoc, build grpc_php_plugin, etc. ...

# Codegen: run the generator with the toolchain present.
FROM toolchain AS codegen
COPY . .
COPY --from=vendor /app/vendor vendor/
RUN ./generate-code.sh        # produces generated sources under /app

# Production: lean, no toolchain.
FROM base AS production
COPY --from=codegen /app /app # only the result — protoc/cmake stay behind
```

If you know exactly where the generator writes, copy just that path (`COPY --from=codegen /app/generated generated/`) plus `COPY . .` and `COPY --from=vendor ...`, so build-only directories (e.g. `node_modules` used only for codegen) don't ride along.

## 4. Correct package-manager cache mounts

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libicu-dev \
        libzip-dev \
        pkg-config
```

Anti-patterns to remove when you see them:

- `rm -rf /var/lib/apt/lists/*` together with a cache mount on that path — wipes the cache for the next build.
- The same `rm` appearing twice in one `RUN`.
- No cache mount at all on a package install (re-downloads every build).
- Missing `--no-install-recommends`.

## 5. Pinned + checksum-verified downloads

Installer binary:

```dockerfile
ADD --chmod=0755 https://github.com/owner/tool/releases/download/2.11.12/tool /usr/local/bin/
RUN echo '<sha256>  /usr/local/bin/tool' | sha256sum -c -
```

Release archive:

```dockerfile
RUN set -eux; \
    wget -q "https://example.com/releases/download/v22.0/pkg-22.0.zip" -O /tmp/pkg.zip; \
    echo "<sha256>  /tmp/pkg.zip" | sha256sum -c -; \
    unzip -qo /tmp/pkg.zip -d /opt/pkg; \
    rm /tmp/pkg.zip
```

If the `sha256sum -c -` step ever fails after a deliberate version bump, that's expected — update the pinned hash for the new version.

## 6. Architecture-aware downloads

When a project builds for multiple CPU architectures, pick the right asset (and its checksum) at build time:

```dockerfile
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64 | i386) zip="tool-linux-x86_64.zip";  sha256="<amd64-sha>" ;; \
      *)            zip="tool-linux-aarch_64.zip"; sha256="<arm64-sha>" ;; \
    esac; \
    wget -q "https://example.com/releases/download/v22.0/${zip}" -O /tmp/tool.zip; \
    echo "${sha256}  /tmp/tool.zip" | sha256sum -c -; \
    unzip -qo /tmp/tool.zip -d /opt/tool; \
    rm /tmp/tool.zip
ENV PATH="/opt/tool/bin:${PATH}"
```

## 7. Secret mounts

```dockerfile
FROM base AS vendor
COPY composer.json composer.lock ./
RUN --mount=type=secret,id=COMPOSER_AUTH \
    export COMPOSER_AUTH=$(cat /run/secrets/COMPOSER_AUTH) && \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader
```

Build with:

```
docker build --secret id=COMPOSER_AUTH,env=COMPOSER_AUTH --target production .
```

The token is available only during that `RUN` and never persists in a layer. If you can't use secret mounts, at minimum confine the credential `ENV` to a throwaway build stage (like `vendor`) that the final image doesn't inherit.

---

## 8. A complete annotated Dockerfile

This combines every pattern: lean `base`, a build-only `toolchain`, a `codegen` stage, a cached `vendor` stage, and sibling `dev`/`production` leaves. Production carries no compilers or generators.

```dockerfile
# syntax=docker/dockerfile:1

# -- Base -- lean runtime: PHP + runtime extensions only. No build toolchain here.
FROM php:8.4-fpm-bookworm AS base

# Pinned + checksum-verified extension installer.
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/download/2.11.12/install-php-extensions /usr/local/bin/
RUN echo '<sha256>  /usr/local/bin/install-php-extensions' | sha256sum -c -

# System libs + core extensions, with correct cache mounts.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libicu-dev libzip-dev libpng-dev libssl-dev pkg-config git unzip \
    && docker-php-ext-install -j"$(nproc)" intl zip pdo_mysql opcache

# Runtime extensions (used at runtime → stay in the lean image). Pinned versions.
RUN install-php-extensions grpc-1.52.1 protobuf-3.22.0 redis-6.1.0

WORKDIR /app   # set once here so every derived stage shares it

# -- Toolchain -- build-only codegen tools; never inherited by production.
FROM base AS toolchain
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends wget cmake
# protoc pinned to MATCH the protobuf runtime above, with checksum + arch detection.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64 | i386) zip="protoc-22.0-linux-x86_64.zip";  sha256="<amd64-sha>" ;; \
      *)            zip="protoc-22.0-linux-aarch_64.zip"; sha256="<arm64-sha>" ;; \
    esac; \
    wget -q "https://github.com/protocolbuffers/protobuf/releases/download/v22.0/${zip}" -O /tmp/protoc.zip; \
    echo "${sha256}  /tmp/protoc.zip" | sha256sum -c -; \
    unzip -qo /tmp/protoc.zip -d /opt/protobuf; rm /tmp/protoc.zip
ENV PATH="/opt/protobuf/bin:${PATH}"
# Build a plugin from source, pinned to the gRPC runtime; parallel make, shallow clone.
RUN set -eux; \
    git clone --depth 1 -b v1.52.1 https://github.com/grpc/grpc /tmp/grpc; \
    cd /tmp/grpc; git submodule update --init --depth 1; \
    mkdir -p cmake/build && cd cmake/build; cmake ../..; \
    make -j"$(nproc)" grpc_php_plugin; cp grpc_php_plugin /usr/local/bin/; \
    cd / && rm -rf /tmp/grpc
RUN protoc --version && command -v grpc_php_plugin   # sanity check

# -- Vendor --
# Cached Composer dependencies. COMPOSER_AUTH is scoped to this throwaway stage, so the
# token never ships in the dev or production images.
FROM base AS vendor
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock ./
COPY .patches/ .patches/
RUN --mount=type=secret,id=COMPOSER_AUTH \
    export COMPOSER_AUTH=$(cat /run/secrets/COMPOSER_AUTH) && \
    composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader

# -- Codegen -- runs generation with the toolchain present; only the result ships.
FROM toolchain AS codegen
COPY . .
COPY --from=vendor /app/vendor vendor/
RUN chmod +x ./.docker/*.sh && ./.docker/generate-code.sh

# -- Dev -- FROM toolchain so engineers can regenerate locally; dev config + debug tools.
FROM toolchain AS dev
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends make \
    && install-php-extensions xdebug pcov \
    && cp /usr/local/etc/php/php.ini-development /usr/local/etc/php/php.ini

# -- Production (default) -- lean: no protoc, no cmake, no compilers.
FROM base AS production
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
COPY --from=codegen /app /app          # app with generated code
RUN chmod +x ./.docker/*.sh \
    && php artisan route:cache \
    && php artisan view:cache          # run shipping-stage build steps here, after code is in place
CMD ["sh", "./.docker/start.sh"]
```

Things to notice in the example:

- `base` has the **runtime** extensions (needed to run) but none of the **build** toolchain.
- `production` is `FROM base`, so it inherits zero of the `toolchain` weight; it receives generated code via `COPY --from=codegen`.
- `protoc` (22.0) and the gRPC plugin (1.52.1) are pinned to match the `protobuf-3.22.0` / `grpc-1.52.1` runtime extensions.
- The credential lives only in `vendor` via a secret mount.
- `WORKDIR /app` is set once in `base`, so `COPY --from=vendor /app/vendor` and `COPY --from=codegen /app` resolve correctly.
