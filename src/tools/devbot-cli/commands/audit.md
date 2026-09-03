---
name: devbot:audit
description: Audit the dev-bot system setup in the current project — verify `devbot reinit` wired things correctly and the local agent can use every dev-bot capability, regardless of which harness (opencode or claudecode) is running. Produces a markdown report of what did not work and why.
---

You are auditing the dev-bot agentic toolkit in this project. The project's own code is irrelevant — only verify that `devbot reinit` set things up correctly and that the local agent can use every dev-bot capability. Work through the checklist, then write an audit report. Prefer the project's `make` targets (inside the container) over raw CLI.

**You audit; you do not fix.** Your job is to surface issues, suggest fixes, and write the report — **do not modify the system** (no config edits, no code changes, no fixes applied, no rebuilds, no reinit). Every issue you discover, however small or cosmetic (a wrong config value, a stale path, a `WARN` in a log, a minor CLI quirk, a race, a misleading message), goes into the report with: the exact evidence, the most likely cause, and a concrete suggested fix (what to change and where). The audit is complete when the report is written — fixing the findings is the developer's job, done separately from the audit.

**Exception — clean up your OWN test artifacts.** "Do not modify" refers to the audited system, not the probe files you create to test it. After writing the report, **delete every probe/scratch file you created** (hook probes, `devbot-audit-probe-*` files, synthetic manifests) from both `thinking/` and `latent/learnings/` — the same promote-or-delete hygiene `devbot:remember-session` mandates for scratch files. Leaving them behind pollutes the memory vault and degrades `search-memories` (15 prior audits accumulated ~98 stale files + 16 probe notes this way — a FAIL in audit-16). Report files and the environment (`.agents/logs`, `graphify-out`, the index) are left as they are.

**Test with LIVE invocations whenever possible — not just filesystem reachability.** A symlink that resolves on disk, a file that exists, or a config that parses is **not proof the capability works** (audit-14's two FAILs — the default agent never being DevBot and 49/59 skills unreachable via the Skill tool — were exactly this: everything looked correct on the filesystem). For each capability, actually USE it: call the MCP tool, fire the hook with a probe, load the skill by name, invoke the command, run the function against real input. Report both the live result and, when they differ, the filesystem-vs-behavior gap.

## 0. Determine the environment: container or host

**First**, establish whether you are running inside a container or directly on the host — every subsequent observation is interpreted through this lens (paths, mounts, docker, GPU, install location, and which values are expected to be "foreign" or "missing" are all environment-dependent).

**Detect** (any of these suffices; cross-check at least two):

- `/.dockerenv` exists → container.
- `grep -q docker /proc/1/cgroup` (or `kubepods`) → container.
- `docker info` fails but `docker` exists on PATH → container (no daemon inside).
- The project dir is a mount like `/app` while the config bakes a host-looking path (e.g. `/home/...`) → container.
- `HOME` looks containerized (`/home/ubuntu`, `/root`) vs the real user's home.

Record the verdict at the top of the report: **ENVIRONMENT: container** or **ENVIRONMENT: host**, plus the evidence.

**The lens — what differs per environment** (apply it when judging every finding):

| Aspect                | Container                                                                                                                                                    | Host                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------- |
| Project dir           | a bind mount (e.g. `/app`) of the host tree                                                                                                                  | the real directory    |
| dev-bot install       | under the container home (e.g. `/home/ubuntu/.local/share/dev-bot`)                                                                                          | under the user's home |
| Docker daemon         | absent (MCP wrappers fall back to npx/direct)                                                                                                                | present               |
| GPU                   | via passthrough (`--gpus all`, `/dev/nvidia*`) — `nvidia-smi` visible                                                                                        | native                |
| Shared state dirs     | host-mounted (`~/.local/share/opencode`, `~/.cache/{qmd,opencode,bun}`, `~/.npm`) — persist across containers                                                | native                |
| Host-side paths       | expected to be **invisible inside the container** (e.g. `JETBRAINS_PROJECT_PATH`, jetbrains `IJ_MCP_SERVER_PROJECT_PATH`, any `/home/<user>/...` in configs) | expected to exist     |
| Container-local state | does NOT persist (ephemeral container) — e.g. caches, the install, fixes made in-session                                                                     | persists              |

**Rules of thumb** (prevent the recurring misdiagnoses):

- A config value that is a host path (`/home/...`) missing inside a container is **expected by design** when it exists to route a host-side service (e.g. jetbrains) — do not flag it; verify the launching env sets it correctly instead (see the jetbrains rule in §4).
- A symlink/cache pointing at the container's install path (`/home/ubuntu/.local/share/dev-bot/...`) that dangles on the host is a **host-side artifact of a container-materialized tree**, not a wiring defect.
- Docker-absent behavior (npx fallbacks, "no docker daemon" skips, container round-trips N-A) is **correct inside a container**.
- GPU verdicts are judged the same in both (the GPU is visible via passthrough), but the ollama container and qmd/opencode installs live on the **host** — inside a container you are auditing the host's services through the network.

## 0b. Detect the harness(es)

First determine which agent harness(es) are wired and which one you are running under, because the MCP config file and tool-naming convention differ per harness.

- **Which harnesses are enabled** — check the `modules` map in `.devbot.project.jsonc` and `.devbot.global.jsonc`: a harness is enabled unless its key (`opencode` or `claudecode`) is present and `false`; absent = enabled. A project may have **both** enabled, in which case both `.opencode/` and `.claude/` exist and both config files are wired. If neither dir exists, `devbot reinit`'s harness step did not run — record that as a FAIL.
- **Which harness you are running under** — look at your own tool palette naming: opencode exposes MCP tools as `<server>_<tool>` (e.g. `qmd_*`, `devbot-tools_*`); claudecode exposes them as `mcp__<server>__<tool>` (e.g. `mcp__qmd__*`, `mcp__devbot-tools__*`). Cross-check with the `harness` key (single value, picks the launch binary) if present.
- **Audit every enabled harness**, not only the one you are running under: each harness has its own MCP config (`opencode.jsonc` vs `.mcp.json`), its own launch command paths, and its own log location. A project with both harnesses enabled must have both configs correct — a broken `.mcp.json` is a defect even if you are currently in opencode.
- **Record it in the report header** — the report MUST state which harness(es) this audit covered and which one the audit ran under, next to the ENVIRONMENT verdict from §0, with the evidence (the `modules` map values + your own tool-palette naming). Without the harness, findings are ambiguous: the same symptom can be an opencode-only bug, a claudecode-only bug, or a harness-gating defect — and log paths, config files, and tool naming all differ per harness. Every FAIL/NOTE row in the report should be attributable to a specific harness (or "both").

## 0c. Identify the running agent (must be DevBot)

The audit is a **DevBot-primary-agent** activity: it must run under the `DevBot` agent profile. Determine which agent you are running as, and cross-check the config:

- **Self-identify** — which agent profile are you operating under? Your own instructions/profile are the primary evidence (DevBot, or TeamLead / a subagent). Do not guess: if you are not certain, check which agent file your instructions came from (e.g. `.agents/agents/devbot/devbot.md` vs `devteam/teamlead.md` vs a subagent file).
- **Cross-check the config** (per the enabled harness):
    - opencode: `opencode.jsonc` → `default_agent` must be `"DevBot"`, and the `agent` map must contain a `DevBot` entry.
    - claudecode: `.claude/settings.json` (or `settings.local.json`) → the default/primary agent must be `DevBot`.

If you are **not** running as DevBot (the audit was launched under TeamLead or a subagent), or the config's default agent is not DevBot, record a **FAIL**: the audit was invoked under the wrong agent. The fix is to **set DevBot as the default agent in the harness configuration** (opencode: `default_agent: "DevBot"` in `opencode.jsonc`; claudecode: the default/primary agent in `.claude/settings.json`) — the harness then launches DevBot by default, so every session (including the audit) runs under the right agent. Findings remain valid, but the "audit runs under DevBot" invariant is broken. Also note it in the report header next to the environment verdict.

## 1. Lifecycle & environment

`devbot reinit` does not create Makefiles or dev containers — those are project characteristics, not dev-bot wiring. Check them only when the project actually has them:

- **Project has a Makefile** — run `make help` and confirm the command list renders; run `make test` (or the scoped test suite) and confirm it passes; confirm the dev container is up (`make up` / `make down` round-trip if feasible).
- **No Makefile** (e.g. a kata project that runs tests via raw `docker run` / `phpunit`) — record this as a NOTE / N-A, **not** a FAIL. It is not a reinit defect.
- **Reinit byte-idempotency (audit-32 NOTE, fixed audit-33)** — `devbot reinit` must be byte-idempotent: snapshot the generated files (`.devbot.project.jsonc`, `AGENTS.md`, `CLAUDE.md`, `opencode.jsonc`, `.mcp.json`) after a reinit, run `devbot reinit` a second time, and byte-compare. FAIL if any file changed. Historic drift causes (all fixed): `remove_mcp_key.py`'s whole-file `json.dump` rewrite expanded compact objects and dropped comments on every reset; the graphify `## graphify` section removal left a trailing blank in AGENTS.md; and reset.sh churned MCP keys that already matched their module templates, reordering the mcp map. NOTE: this probe is also wired into the harness launchers (`test-reinit.sh` prints BYTE-IDEMPOTENCY-PASS/FAIL after its own reinit).

## 2. Hooks (manifest-driven)

- Edit a `.md` file and confirm the format-md hook reformats it.
- Edit a `.json`/`.jsonc` and a `.yml` file — confirm format-json / format-yml fire.
    - **Burst-edit probe (audit-32 FAIL, fixed audit-33)**: write + edit the same `.yml` within ~1s and confirm the file is NOT corrupted. The opencode adapter previously ran one format hook per `file.edited` with no per-file serialization, so two concurrent prettier runs interleaved their read-modify-writes and mixed 2/4-space indentation (a second, non-raced probe behaved correctly). `on-hooks.ts` now serializes + coalesces `file.edited` per path.
- Attempt a guarded command (e.g. `rm -rf /tmp/x`) and confirm the guards hook blocks it.
    - **Live enforcement (audit-32 FAIL, fixed audit-33)**: this must be tested LIVE on opencode — the engine CLI alone is not enough. The opencode adapter previously read `process.env.DEVBOT_ROOT` (never exported — the harness exports `DEV_BOT_ROOT`), so `--global-config ""` merged no rules and `rm -rf`/`sudo` ran unblocked even though `guards.ts` alone returned `blocked:true`. The adapter now resolves the global config from its own root (the realpath already used for manifest loading), falling back to the env var.
- If a K8s manifest is present, edit it and confirm lint-k8s fires.

## 3. Skills

- Trigger skills by intent and confirm they load — e.g. git commit guidance → `devbot:git-conventional-commits`, a small change → `test-driven-development`, project exploration → `devbot:create-project-report`.

## 4. Tools (MCP palette)

- Invoke tools directly (e.g. `search-memories`, `devbot:git-report`, `devbot:tree`, `devbot:format-md`, `devbot:qmd`) and confirm each returns output.
- Confirm the `devbot-tools` MCP tools are discoverable and return `mcp-meta` correctly.
- **MCP server health** — a registered-but-unconnected MCP server is a FAIL. Repeat this block per enabled harness.

    **opencode** — (1) Enumerate the servers from the `mcp` block in `opencode.jsonc`. (2) For each, confirm its tools are reachable in your own tool palette — opencode names them `<server>_<tool>` (e.g. `qmd_*`, `devbot-tools_*`, `codebase-index_*`, `graphify_*`, `context7_*`, `chrome-devtools_*`, `playwright_*`, `jetbrains_*`); a server with no matching tools is not connected. (3) Find the cause: grep the newest `~/.local/share/opencode/log/*.log` for `server unavailable` and `status=failed` — opencode logs `message="server unavailable" key=<server> type=local status=failed` when a local MCP server fails to launch (the timestamp distinguishes a launch race from a hard failure). (4) Diagnose per-server from its launch command — e.g. graphify's wrapper (`bash .opencode/graphify-serve.sh graphify-out/graph.json`) exits 0 silently when `graph.json` is absent, so a fresh `devbot reinit` often launches it before the graph is built; reloading the session recovers it.

    **jetbrains** — the `IJ_MCP_SERVER_PROJECT_PATH` header reflects the **launch-time `JETBRAINS_PROJECT_PATH` env var** (set by the harness launchers to the HOST-side project root so the host IDE — reached via `--network host` — can route the correct project). The header is therefore expected to be a HOST path that does **not** exist inside a container. Do NOT flag a header whose path is missing in the container — that is the design. Instead verify: (a) the launcher sets `JETBRAINS_PROJECT_PATH` to the real host project root, and (b) the server connects (tools respond). Only flag when the env is absent/unset at launch (header falls back to the container path, which the host IDE cannot resolve) or the server fails to connect. If `get_project_modules` returns a different project than expected, that is the IDE's currently-open-project state, not a config defect.

    **claudecode** — (1) Enumerate the servers from the `mcpServers` block in `.mcp.json`. (2) For each, confirm its tools are reachable in your own tool palette — claudecode names them `mcp__<server>__<tool>` (e.g. `mcp__qmd__*`, `mcp__devbot-tools__*`, `mcp__codebase-index__*`, `mcp__graphify__*`, `mcp__context7__*`, `mcp__chrome-devtools__*`, `mcp__playwright__*`); a server with no matching tools is not connected. (3) Find the cause: claudecode logs MCP connection failures under `~/.claude/logs/` **when that directory exists**; in current Claude Code CLI builds it does not — the per-server connection logs live at `~/.cache/claude-cli-nodejs/<project-slug>/mcp-logs-<server>/*.jsonl` (one file per session, JSON lines with `error`/`debug` fields). Check both: grep for the server name plus `failed to connect` / `MCP` (the signature differs from opencode's `server unavailable`; adapt as needed). (4) Diagnose per-server from its launch command — e.g. graphify's wrapper (`bash .claude/graphify-serve.sh graphify-out/graph.json`) has the same `graph.json`-absent launch race as opencode. (5) **jetbrains**: the `IJ_MCP_SERVER_PROJECT_PATH` header is the launch-time `JETBRAINS_PROJECT_PATH` env (HOST-side path for the host IDE) — a path missing inside the container is expected, not a defect; verify the launcher sets it and the server connects (see the opencode block for the full rule).

    Report every unavailable server in the FAIL table with the harness, the exact log line, and the likely cause.

- **GPU usage (qmd + codebase-index)** — first determine whether the environment actually has GPU access, then verify each GPU-dependent capability either uses it or correctly falls back:

    **Environment GPU** — `nvidia-smi` (or `/dev/nvidia*` for NVIDIA, `/dev/dri/renderD*` for Intel/AMD). Record present/absent and the driver version. This is the ground truth everything below is judged against.

    **qmd** — (1) Read the qmd MCP env in the harness config (opencode: `mcp.qmd.environment.QMD_LLAMA_GPU` in `opencode.jsonc`; claudecode: the `mcpServers.qmd` env). (2) Run `qmd doctor` and read the model-cache line and the device line (`GPU acceleration` / `running on CPU`). (3) Cross-check config vs reality:
    - GPU **present** → qmd should report GPU acceleration (config `true`/auto, doctor device probe GPU). FAIL if qmd runs CPU-only while a usable GPU exists (report the config value and doctor's device line).
    - GPU **absent** → qmd must NOT be configured to force GPU (`QMD_LLAMA_GPU=true` makes qmd attempt a GPU backend and hang/fail). FAIL if the config forces GPU with no GPU available; CPU is the correct fallback.

    **codebase-index** — embeddings go through ollama. (1) Read the provider config (`.opencode/codebase-index.json` — `customProvider.baseUrl` / `embeddingProvider`). (2) Check the ollama API (`curl <baseUrl>/api/tags` — is the embedding model present?). (3) Check whether the serving ollama uses the GPU — `curl <baseUrl>/api/ps` shows running models with VRAM usage (`size_vram` > 0 = on GPU), or `nvidia-smi` shows an ollama process with memory. Cross-check:
    - GPU **present** → the embedding model should be served with GPU acceleration. FAIL if ollama runs it CPU-only while a GPU is available and usable (report `api/ps` or `nvidia-smi` evidence).
    - GPU **absent** → ollama runs CPU — acceptable; FAIL only if it attempts GPU and fails.

    Report every mismatch in the FAIL table with the config value, the runtime evidence, and the likely cause.

## 5. Memory

- **Passive-memory round-trip**: write a note under `.agents/memory/latent/learnings/` with a unique marker (e.g. `devbot-audit-probe-<timestamp>`) and a distinctive phrase, then run `search-memories` for that phrase and confirm the note is returned. This verifies the write → passive reindex → search round-trip. If it isn't found immediately, the passive reindex (`qmd update && qmd embed`) may still be running in the background — run `qmd update` (or wait) and re-search.
- **Project memories — explicitly verify**: run `search-memories` for a phrase that exists only in the **project** vault (`.agents/memory/latent/`) and confirm the result's file path is under the project vault — not the global store. This proves the project collection is registered and searchable. (If the project vault has no seeded content yet, write the probe note above first, then search for its marker.)
- **Global memories — explicitly verify**: run `search-memories` (or `qmd search`) for a phrase that exists only in the **global** store (`storage/global-memories/` — the shipped knowledge base symlinked as `.agents/memory/latent/global`) and confirm the result's file path is under `global/` (or the global collection `dev-bot-global`), not the project vault. This proves the `latent/global` symlink and the `dev-bot-global` QMD collection are wired. Good probe phrases: a distinctive tech-gotcha keyword that only lives in the global store — e.g. search a term from a `storage/global-memories/<tech>/` filename you can see exists. If `search-memories` returns nothing for a global-only phrase while `qmd search` (or the `dev-bot-global` collection directly) does, record the mismatch — the tool's global-collection wiring is broken.
- **Both must return results**: the audit must show evidence of at least one project-vault hit AND at least one global-store hit. A memory section that only verified one of the two stores is incomplete — record which store was not proven searchable as a FAIL (the `latent/global` symlink, the `dev-bot-global` collection registration, or the search tool's collection wiring may be broken).
- **Concurrent-process races in the logs**: when scanning `hooks.log`, `qmd-index.log` and the reindex paths, watch for signatures of two processes racing the same resource — `SQLITE_CONSTRAINT` / `constraint failed`, `SQLITE_BUSY` / `database is locked`, primary-key collisions, "already running", or duplicate background jobs stacking. A single file edit firing several hooks at once is normal; it must be safe (coalescing locks, pidfiles, upserts). FAIL if the logs show such race signatures or a hook/tool that can be invoked concurrently runs its work unguarded.
- **Delete → prune self-heal (live — audit-28/29 FAIL, fixed audit-30; mechanism moved to start.sh in audit-36)**: deleting a memory note must stop it surfacing in search. Write a probe note (as in the round-trip above), wait until `search-memories` returns it, then `rm` it. Neither harness delivers a delete event for external (bash) deletions — opencode 1.18.26 emits no watcher unlink and claudecode has no delete event — so the self-heal runs **at launch**: `devbot` start.sh fires a detached `reindex-memories prune` (`qmd cleanup && qmd update`, no embed) before the harness boots, logging a `[reindex-memories-prune-start]` marker plus the tool's `{"status":"started",...}` JSON to `.agents/logs/qmd-index.log`. Cross-check that log for the marker. FAIL if the stale entry persists after a fresh `devbot`-launched session with no marker (prune not fired). A note deleted mid-session may briefly surface until the next launch — expected, not a defect. NOTE: a harness launched directly (bare `opencode`/`claude`, bypassing start.sh) does not fire the prune — `devbot` is the canonical launch path.
- **Default collection resolution (audit-32/33 FAIL, fixed audit-33)**: run `search-memories` with NO `--collection` and confirm it succeeds. Both harnesses FAILed with `Collection not found: devbot` because `search-memories.py resolve_collection()` fell back to the literal `"devbot"` while `qmd/init.sh` registers the collection under the project-dir basename — the two files that must agree on a default disagreed. Fixed by (a) `resolve_collection()` now falls back to `Path(project_root).name` (mirroring `qmd/init.sh` exactly, including empty-`project_name` → basename) and (b) `devbot-cli/init.sh` injects a missing `project_name` (dir basename) into an existing `.devbot.project.jsonc` on reinit. FAIL if a default (no `--collection`) search errors.
- Trigger `devbot:remember-session` (or the finish flow) and confirm it captures learnings to the vault.
- Run `search-memories` and confirm results.
- Confirm the finish flow asks "are you finished?" instead of emitting `[FINISHED]` directly.

## 6. Commands

- Invoke another slash command (e.g. `/devbot:commit`) and confirm it runs.

## 7. Agents & orchestration

- Confirm agent profiles load (DevBot / TeamLead plus subagents).
- If TeamLead is exercised, confirm context gathering (@scout) and the TODO-list discipline fire.

## 8. Log examination

At the end, examine the runtime logs for issues that no live tool call would surface. First determine which harness(es) are enabled (section 0: the `modules` map in `.devbot.project.jsonc` / `.devbot.global.jsonc` — a harness is enabled unless its key is `false`). To know which harness you are currently running under, look at your own tool palette naming: opencode exposes MCP tools as `<server>_<tool>` (e.g. `qmd_*`, `devbot-tools_*`); claudecode exposes them as `mcp__<server>__<tool>` (e.g. `mcp__qmd__*`, `mcp__devbot-tools__*`) — cross-check with the `harness` key (single value, picks the launch binary) in the configs. Then examine the logs in this order:

### 8a. Project MCP logs — `.agents/logs/` (shared by all harnesses)

The devbot dir's MCP server logs. Enumerate `*.log` files, then inspect each for error signatures. Known healthy signatures to distinguish from real issues: the `devbot-tools-mcp.log` `discovered N tool(s)` line, the `chrome-devtools-mcp.log` startup banner, empty `graphify-mcp.log` / `playwright-mcp.log`, and stray terminal escape sequences (e.g. `[?25h`) in `qmd-mcp.log`. Real issues look like stack traces, `error`/`failed`/`fatal` lines, or crash loops (a log growing unboundedly with restarts). Report anything that is not a known-healthy signature.

**Report output vs genuine errors**: error-like words in the logs are NOT automatically failures. A linter/formatter/validator writes its _findings summary_ as report output (e.g. kube-linter's `Error: found N lint errors`, prettier reporting a file as "failed") — that is the tool reporting, not a session error. When a log line matches an error pattern, ask: is this a tool REPORTING findings, or a runtime FAILURE (crash, launch failure, unhandled exception, timeout)? Distinguish by context — report logs (`lint-k8s.log`, formatter/linter output) legitimately contain error-like words; runtime logs (`hooks.log`, MCP server logs) should only contain them on genuine failures. Verify the end-of-session alert (`_devbot_check_session_logs` in `src/_shared/functions.sh`) applies the same discrimination (report-style logs excluded, real errors still flagged). FAIL only when a genuine runtime failure is present or when the alert misclassifies a report as an error.

### 8b. Harness log(s) — repeat per enabled harness

Each harness keeps its own runtime log; audit the log of every enabled harness, not only the one you are running under:

| Harness    | Log location                                                                                                                                      | Failure signatures to grep                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| opencode   | `~/.local/share/opencode/log/opencode.log`                                                                                                        | `message="server unavailable" … status=failed` (MCP launch failures) |
| claudecode | `~/.claude/logs/` when present; current CLI builds instead use `~/.cache/claude-cli-nodejs/<project-slug>/mcp-logs-<server>/*.jsonl` (check both) | MCP `failed to connect` / `MCP` error lines                          |

Also grep the harness log for plugin/runtime errors that surface to the TUI but not to any file log, e.g. `Failed to load native module` and `fatal: not a git repository` (the latter is expected noise in a non-git project — record it as a NOTE, not a FAIL, unless it accompanies a broken capability).

Known third-party noise signatures — record as NOTE, not FAIL, unless they escalate: context7's per-session `subscriptions/listen re-open attempt N failed: Subscription limit reached` in `mcp-logs-context7/*.jsonl` (server-side subscription cap on the hosted server; tool calls still succeed; report upstream only if the retries grow or calls start failing).

Fold anything found into the report's FAIL table (or NOTES) with the log line and likely cause.

## 9. External modules (install + wiring)

External modules are the one dev-bot feature with a registration CLI (`devbot module add`) plus a separate wiring pass (reinit's `external-modules/init.sh`), so audit them **live end-to-end** — filesystem reachability is not enough.

- **Inventory** — list every entry under `external_modules` in `.devbot.global.jsonc` (both modules declared by internal `external-modules.json` files and user/CLI `module add` entries). For each confirm: the source resolves (vendor clone for `url`, existing dir for `local_path`); it is wired as `.agents/<type>/<name>` per its `paths` map in the project's devbot dir; and its storage mirror exists under `storage/external-agentic-modules/<name>/`.
- **Install all external modules** — run the install path (`devbot module install`) and confirm every `url` entry clones/updates and every `local_path` entry is verified without cloning.
- **Local-path module end-to-end** — create a dummy local module (a temp dir with `skills/` and/or `agents/` subdirs containing a `SKILL.md` / agent file), register it with the official CLI (`devbot module add <dir>`), then run `devbot reinit`. Confirm the dummy is wired into the project's `.agents/skills/<name>` (and agents/commands per detected paths) and mirrored in storage. This is the documented user flow — a registered module that reinit does **not** wire is a FAIL (audit-29 FAIL-1).
- **Git module variant** (optional, offline-safe) — repeat with a `file://` url or a pre-cloned vendor dir via `devbot module add <url>`.
- **Revert** — afterwards `devbot module remove <name>`, delete the dummy source / vendor clone / storage dir, re-run reinit, and confirm the fixture is back to its pre-test state (no dummy references in configs, no broken symlinks). Audit-29's §9 shows the expected pass/fail matrix and cleanup.

Fold any finding into the FAIL table with the config entry, the observed wiring state, and the likely cause (declaration gate in `external-modules/init.sh`, `_discover_projects()` scope, `_unwire_module` coverage, etc.).

## Report

At the end, produce an audit that answers only these two questions (project specifics are irrelevant):

1. **Did `devbot reinit` set things up correctly?** — lifecycle scripts, module wiring, harness adapters, MCP registration.
2. **Can the local agent use all dev-bot capabilities?** — skills, tools, hooks, commands, memory, agents.

### Write the report to a file

Write a markdown report to `.agents/memory/thinking/devbot-audit-NN.md` (`.agents` is the devbot dir from config), where `NN` is the next sequential integer starting at `01` — first list the existing `devbot-audit-*.md` files in that directory, then use the next number (e.g. `01` if none exist, `02` after `01`, …).

**Open the report with a header block** stating the audit context — every report MUST begin with these three lines before any findings (they let a reader interpret the whole report without re-deriving the environment):

- **ENVIRONMENT: container** or **ENVIRONMENT: host** — plus the evidence (from §0).
- **HARNESS(ES) ENABLED** and **HARNESS THIS AUDIT RAN UNDER** — which harness(es) are wired (`modules` map) and which one this session used (tool-palette naming), plus the evidence (from §0b). If both harnesses are enabled, the audit covers both — say so, and attribute every FAIL/NOTE below to a specific harness.
- **RUNNING AGENT** — `DevBot` (or the FAIL if not, per §0c).

For each subsystem, record:

- **PASS** — what worked and the evidence (tool output, hook firing, etc.).
- **FAIL / NOTE** — every problem found, however small, with the exact error/output observed, the most likely known cause, and a **suggested fix** (what to change and where). Do NOT apply fixes — the report surfaces them for the developer.
- **FAIL** — what did NOT work, the exact error/output observed, and the most likely known cause (e.g. "format-md hook didn't fire — the on-hooks adapter may not be wired"; "tool returned no output — MCP server not registered"; "graphify MCP not connected — `server unavailable … status=failed` in the opencode log (launch race: `graph.json` absent at session start)"). Note: every FAIL must be resolved (see the fix mandate above) before the audit is complete — there is no such thing as a "cosmetic" or "minor" finding that gets reported without a fix.

End the file with a summary table:

| Subsystem | Status | Evidence | Likely cause (if failed) |
| --------- | ------ | -------- | ------------------------ |
| …         | …      | …        | …                        |

### Summarize to the user

Then give the user a short summary: the two questions answered, the list of failures with their likely causes, and the path to the written report file.
