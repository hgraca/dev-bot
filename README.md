<div align="center">

<img src="docs/imgs/icons/devbot-icon-512.png" alt="DevBot" width="120" height="120">

# DevBot

**Everything for agentic software development.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/Docs-Read_the_docs-blue)](https://get-e.github.io/dev-bot/)
[![Harness: OpenCode](https://img.shields.io/badge/Harness-OpenCode-6c7bff)](https://opencode.ai/)
[![Harness: Claude Code](https://img.shields.io/badge/Harness-Claude_Code-d97757)](https://www.anthropic.com/claude-code)

</div>

DevBot is a **meta-harness** for the GET-E engineering team. It installs a complete
agentic development workflow — a pair programming agent, persistent memory shared
across colleagues and codebases, curated skills, and managed MCP servers — into
[OpenCode](https://opencode.ai/) or [Claude Code](https://www.anthropic.com/claude-code).

It serves a **dual purpose**:

1. **Pair Programming Agent (daily driver):** works alongside you in small
   increments — exploring, designing, and writing together. It primes context at
   session start, recalls past decisions, and loads the right skills for the job.
   It is never autonomous; you stay in control.
2. **Multi-Agent Orchestrator (power user):** classifies work and routes it to
   specialized subagents — Architect, Developer, Tester, Reviewer, Critic, PO,
   Scout, Security — in structured plan → implement → review cycles with verified
   deliverables at every gate.

This README is a brief overview. For comprehensive details, see the
[full documentation](https://get-e.github.io/dev-bot/).

---

## Why DevBot?

- You work in several projects, each should have their own memory and also a shared global memory
- You work in a team and you want to share and build your projects knowledge bases (memories) together
- You work in a team where members are using different harnesses but you want everyone's agents working in the same way, with similar outputs and outcomes
- You want your agents to have all skills they need to develop projects following industry best practices
- You want a set of curated MCPs for your agents to use
- You work with several harness instances open but don't want to duplicate MCP servers with each instance

---

## Quick Start

### Install

The repository is private, so the installer is served from the docs site:

```shell
curl -fsSL https://get-e.github.io/dev-bot/install.sh | bash -s -- --ssh
```

> [!NOTE]
> `--ssh` clones over SSH (`git@github.com:GET-E/dev-bot.git`). Drop it to clone
> over HTTPS, or pass `--org <org> --repo <repo> --branch <branch> --host <host>`
> to install from a fork. From an existing clone, `make install` runs the same
> installer.

Configuration is read from `.devbot.global.dist.jsonc`, copied to
`.devbot.global.jsonc` on install. Edit it to change `modules`, `guards`, or
`external_modules` before installing.

### Initialize a project

```shell
cd path/to/your-project
devbot init
```

This wires the agents, commands, skills, tools, and MCP servers into the project.
To override the global configuration for one project, edit
`.devbot.project.jsonc` and run `devbot reinit`.

### Start working

```shell
devbot
```

Brings up the local services and starts the configured harness. Use `devbot up`
to start only the services, and `devbot help` to list every command.

### Prime the project context

Run this once per project, from inside the agent session. It writes
`.agents/memory/active/project.md` — the bootstrap description every agent reads
at session start:

```shell
/create-project-report
```

### Manage services and updates

```shell
devbot down     # stop the local services
devbot update   # update to the latest release tag
```

---

## Development

Working on DevBot itself needs the runtime prerequisites plus one parallel
runner for the shell test suite:

| Tool                     | Why                                                               | Install                                          |
| ------------------------ | ----------------------------------------------------------------- | ------------------------------------------------ |
| `bats` + support libs    | Shell test suite — the bulk of `make test`                        | `npm install -g bats bats-assert bats-support`   |
| GNU `parallel` or `rush` | Runs the BATS suite in parallel; without it `make test` is serial | `apt install parallel` · `brew install parallel` |
| `bun`                    | TypeScript test suite and the `.ts` tools                         | `curl -fsSL https://bun.sh/install \| bash`      |
| `python3`                | `src/_shared` helpers and the Python test suite                   | system package manager                           |

> [!NOTE]
> GNU `parallel` is preferred; `rush` is picked up automatically when it is the
> only one on `PATH` (install from its
> [releases](https://github.com/shenwei356/rush)).

`make test` runs all three suites — BATS, `bun test src/`, then the Python
unittests. The BATS stage accounts for ~99% of the runtime, so that is the one
parallelised. The job count defaults to the CPU count, capped at 8; override it
with `DEV_BOT_TEST_JOBS`:

```shell
make test DEV_BOT_TEST_JOBS=4
```

> [!NOTE]
> No CI runs the test suite — `make test` is the only gate, so run it before
> every commit.

---

## Documentation

The documentation site is published at
[get-e.github.io/dev-bot](https://get-e.github.io/dev-bot/).

Most of the site is **generated from the source modules**. Every module that
ships a `docs.md` gets a page at `/modules/<area>/<name>`; the module index, the
navigation menu, and the aggregate pages (Agents, Skills, Slash commands, Hooks,
MCPs, Module Reference) are built from the module files at compile time. A module
without a `docs.md` gets no page and no link anywhere on the site.

`make docs` gathers the module pages and serves the site; `make docs-gather`
builds them without serving.

The hand-written pages under [`docs/`](docs/) are:

1. [Configuration](docs/configuration.md)
2. [Create a module](docs/create-a-module.md) — module anatomy and the `docs.md` contract
3. [MCP configuration](docs/mcp-config.md)
4. [Modules & tools map](docs/modules-and-tools.html)

> Per-module documentation lives beside each module (`src/<area>/<module>/docs.md`),
> not under `docs/`.

---

## License

Released under the [MIT License](LICENSE).
