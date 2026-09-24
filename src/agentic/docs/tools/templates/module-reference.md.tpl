---
layout: page
title: "Module Reference"
description: "DevBot modules — self-contained capability units."
nav_section: docs
---

## Module anatomy

Every module follows the same structure under `src/agentic/<name>/`. **All entries are optional** — a module includes only what it needs:

```
<module>/
  agents/               Agent profiles
  commands/             Repeatable instruction sets invocable via agent input
  skills/               Agent-readable skill instructions (SKILL.md per skill)
  hooks.json            Declarative hook manifest (harness-agnostic)
  hooks/git/            Git hooks (optional)
  tools/                Executable tools (`.sh` CLI wrappers, `.py`/`.ts` helpers)
    opencode/           TS thin wrapper for the OpenCode tool palette
    claudecode/         MCP server script (e.g. graphify's mcp-server.js)
  memory/               Bootstrap files symlinked into `.agents/memory/` (external modules)
  tests/                BATS test suite
  docs.md               User-facing documentation for this site (optional)
  install.sh            Idempotent OS dependency installer
  update.sh             Dependency update script
  init.sh               Per-project init + dependency self-heal
  up.sh                 Post-docker startup script
  down.sh               Pre-teardown script
  pre.sh                Prerequisites check
  reset.sh              Per-project state reset
  start.sh              Launch the harness binary (harnesses only)
  stats.sh              Tool/MCP usage adapter for `devbot stats` (harnesses only)
  functions.sh          Thin wrapper sourcing `src/_shared/functions.sh`
  mcp.json              Canonical MCP server manifest (harness-agnostic — see [MCP configuration](/mcp-config))
  plugin.opencode.json  OpenCode plugin names declared by this module (optional)
  external-modules.json External module dependencies declared by this module
  versions.env          Dependency version pin: installed exactly at install, bumped by `update.sh` (optional)
  skills-prune.lst      Tool-installed skill duplicates this module declares for auto-pruning (optional)
  docker-compose.yml    Module-owned docker service(s), auto-discovered by `devbot up`/`down` (optional)
  docker-compose.gpu.yml  GPU passthrough overlay for this module's service, included when GPU is available (optional)
  Dockerfile            Image build for a module-owned service (optional)
```

### Documentation (`docs.md`)

A module that ships a `docs.md` gets a page on this site at `/modules/<area>/<name>`; a module without one gets no page and no reference anywhere. The page is built at compile time — see [Create a module](/create-a-module) for the front-matter contract (a required `description` plus a concise capability manifest).

### Lifecycle scripts

**install.sh**: Idempotent — can be run multiple times safely. Installs OS-level dependencies. Run automatically by `bin/install.sh` which loops over all modules.

**update.sh**: Updates dependencies to latest compatible versions. Run by `bin/update.sh`.

**pre.sh**: Checks module prerequisites (Python 3, API reachability, etc.). Run automatically by `bin/install.sh` and `bin/update.sh`. Must be idempotent and non-destructive. Warnings (not errors) for optional deps.

**init.sh**: Per-project initialization and idempotent dependency self-heal. Run by `bin/init.sh`. Use this hook to close the update/reinit gap — `devbot update` runs only `update.sh` while `devbot reinit` runs only `init.sh`, so anything an adopting install would otherwise miss has to be healed here.

**up.sh**: Post-docker startup script. Use for pulling models, waiting for services, seeding data.

**down.sh**: Pre-teardown script. Run by `bin/down.sh` before docker services stop — for **every** module, disabled ones included (`--all`), because a module disabled in this project may still own a non-compose container to reap (playwright's `docker run` orphans).

**reset.sh**: Resets per-project state. Run by `bin/reinit.sh` (`devbot reinit`) before re-running init.

**start.sh** (harnesses only): Launches the harness binary (`claude` / `opencode`) without forcing an agent — the session agent comes from the project's default (`opencode.jsonc` `default_agent` / `.claude/settings.json` `agent`), created with DevBot by default during init and only asked about when an existing config chose a different agent. Run by `devbot` (`cmd_harness` in `bin/devbot`) to start the configured harness; not part of the generic lifecycle loops. Accepts an optional project directory as `$1` and forwards remaining args to the harness binary. Before launching it rotates the previous session's `.agents/logs/*.log` files to `.agents/logs/rotated/<date>-<name>-<NNN>.log`, then runs the harness as a child (not `exec`); on exit it scans the fresh logs for error-level lines, alerts the user, and exits with the harness's exit code.

### Dependency version pins (`versions.env`)

Modules that install an external CLI/MCP dependency globally (e.g. chrome-devtools, playwright) keep its version in `versions.env`. `install.sh` installs exactly the pin and is idempotent; `update.sh` resolves the package's npm latest on `devbot update`, installs it, and rewrites the pin in place — session start never re-resolves `latest`. Runtime launch commands resolve the installed binary by explicit npm-prefix paths (never bare-name via PATH, which can pick up a stale system binary).

### Module-owned docker services (`docker-compose.yml`)

A module that needs a long-running service ships its own `docker-compose.yml`; `bin/up.sh`/`down.sh` discover it (maxdepth 2 under each module dir) and start/stop it. **`up` is gated by the `modules` map** — the service starts only while the module is enabled. **`down` is not**: containers are install-level, so removal selects every discovered compose and is gated on the session registry instead (see [CLI commands](/modules/tools/devbot-cli)). Every dev-bot compose file declares `name: devbot` so all containers land in one compose project regardless of which file is listed first.

A service that builds its own image adds a `Dockerfile` next to the compose file, and anchors the build context on the absolute `DEV_BOT_ROOT` — `build: { context: ${DEV_BOT_ROOT}/src/<area>/<module> }`. Never a relative `.`: `bin/up.sh` lists every selected module compose as one `-f` list, and compose resolves a relative context against the **first** file's directory rather than the file's own, so the build reads whichever module is listed first — the fresh-install failure `failed to read dockerfile: open Dockerfile: no such file or directory`, which appears only where no image exists yet (an existing image means compose never builds). The same rule governs a relative `include:`. `docker compose up` builds the image on first start when it is missing, and `bin/up.sh` rebuilds it when the Dockerfile changes; a manual rebuild needs the variable set (`bin/up.sh` and `bin/down.sh` both export it): `DEV_BOT_ROOT="$(pwd)" docker compose -f <module>/docker-compose.yml build`.

A module that needs GPU passthrough adds a `docker-compose.gpu.yml` beside its compose. It is included only when GPU passthrough is available (`gpu_enabled` **and** a live probe) **and** that module's compose is selected — the overlay follows the compose it overrides, so it can never be applied without the service it targets. A module that runs no container of its own but needs a GPU provider (codebase-index needs ollama) ships an overlay that `include:`s the provider's, mirroring how its compose includes the provider's compose.

Such a consumer overlay exists only for the case where the provider's **module** is disabled. When the provider's module is enabled, its own overlay is applied directly and the consumer's would merge the same device reservation a second time. A consumer overlay therefore declares which compose it stands in for, and is skipped when that compose is already in the set:

```yaml
# devbot:gpu-overlay-skip-if-included src/tools/ollama/docker-compose.yml
```

`bin/up.sh` reads that marker via `_gpu_overlay_skip_if` and logs the skip. Only `up` needs it: `down` applies no GPU overlays at all (a teardown needs no device reservations), so the two commands do not select the same compose set — `up` is module-filtered and overlay-aware, `down` is machine-wide.

Used by the shared MCP gateways — see [MCP configuration](/mcp-config#shared-machine-wide-gateways).

### Declarative skill prunes (`skills-prune.lst`)

External tools sometimes install duplicate copies of a skill a module ships (e.g. the graphify CLI copies its unnamespaced `graphify` skill into project skill dirs, and a module's `init.sh` can only strip them while the module is **enabled**). A module declares such duplicates in `skills-prune.lst`, one per line:

```
# skill-name  ownership-marker-file
graphify .graphify_version
```

Harness inits run `_prune_stale_skill_copies` (`src/_shared/functions.sh`) on every skills location they own — opencode prunes `<devbot_dir>/skills` after delegation; claudecode prunes `.claude/skills` **and** `<devbot_dir>/skills` before the skills flatten. A directory named `<skill-name>` or `<skill-name>.bkp*` is removed only when it carries the declared marker (the installing tool's own signature file), so user content is never touched. Declarations are honoured regardless of module enablement — pruning a disabled module's leftovers is exactly the point.

### Machine-local skill overrides (`storage/<module>/skills`)

A module can produce a machine-local, generated skill under `<DEV_BOT_ROOT>/storage/<module>/skills` — graphify regenerates its `devbot:graphify` skill from the installed CLI so it tracks the installed graphify version, in or outside the dev-bot lifecycle. When that directory carries a `.devbot-generated` sentinel, `_link_skills` (`src/tools/devbot-cli/functions.sh`) and the claudecode flatten point the module's farm entry at it instead of the committed `<module>/skills/` (under `src/agentic` or `src/tools`), which stays the fallback whenever generation is impossible. The sentinel is the opt-in: a module that merely writes `storage/<name>/skills` for its own wiring (e.g. signoz) is never farmed here. The generated dir is gitignored (under `storage/`); the committed skill is never rewritten.

### Hooks

Hooks are declared in a per-module `hooks.json` manifest (harness-agnostic) and wired by one generic adapter per harness — `on-hooks.ts` (OpenCode) and `on-hooks.py` (Claude Code). Business logic lives in `tools/`; the manifest's `run` command references it via `{module}/tools/…`. See [Hooks](/hooks) for the schema, the six semantic events, and the hand-written `devbot:auto-recover` exception.

### Tools

When a tool is present, it must:

- Contain a bash script so the user can trigger it directly
- Default output format: Markdown
- Agent tools (TS/JS wrappers around the bash script) default to JSON to save tokens

`.ts` files are the authoritative source of truth — business logic lives there. `.sh` files are thin CLI wrappers that delegate to `.ts` via `bun run`. They never contain business logic.

### Testing

Tests use the **bats** framework (Bash Automated Testing System). Install via `npm install -g bats bats-assert bats-support`. `make test` auto-installs bats if missing.

Test fixtures go in `<module>/tests/fixtures/` and should be minimal — create what is needed for the test, clean up after.

---

## Internal modules

Located at `src/agentic/<name>/`. Each provides agent skills, tools, hooks, agents, or MCP servers.

<!-- GENERATED:MODULES_INTERNAL -->

**S** = Skills, **T** = Tool scripts, **C** = Commands, **A** = Agents, **H** = Hook scripts (opencode `.ts` + claudecode `.sh`), **MCP** = MCP server

---

## Tools modules

Located at `src/tools/<name>/`. Infrastructure services — Docker Compose, CLI lifecycle, project initialization.

<!-- GENERATED:MODULES_TOOLS -->

**Disabled by default**: `litellm` is skipped during install/update/init unless overridden in `.devbot.global.jsonc`.

---

## Harness modules

Located at `src/harnesses/<name>/`. The agent runtimes DevBot plugs into — see [OpenCode](/modules/harnesses/opencode) and [Claude Code](/modules/harnesses/claudecode).

---

## External modules

Third-party modules registered via `devbot module add` and wired into projects via symlinks. They follow the same anatomy as internal modules and can provide agents, skills, commands, hooks, tools, and memory bootstrap files.

See [External modules](/modules/tools/external-modules) for the registry, the `devbot module` CLI, and the configuration format.
