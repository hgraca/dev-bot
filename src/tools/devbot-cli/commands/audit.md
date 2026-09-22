---
name: devbot:audit
description: Audit the dev-bot system setup in the current project — verify `devbot reinit` wired things correctly and the local agent can use every dev-bot capability, regardless of which harness (opencode or claudecode) is running. Produces a markdown report of what did not work and why.
---

You are auditing the dev-bot agentic toolkit in this project. The project's own code is irrelevant — only verify that `devbot reinit` set things up correctly and that the local agent can use every dev-bot capability. Work through the checklist, then write an audit report. Prefer the project's `make` targets (inside the container) over raw CLI.

**You audit; you do not fix.** Your job is to surface issues, suggest fixes, and write the report — **do not modify the system** (no config edits, no code changes, no fixes applied, no rebuilds, no reinit). Every issue you discover, however small or cosmetic (a wrong config value, a stale path, a `WARN` in a log, a minor CLI quirk, a race, a misleading message), goes into the report with: the exact evidence, the most likely cause, and a concrete suggested fix (what to change and where). The audit is complete when the report is written — fixing the findings is the developer's job, done separately from the audit.

**The audit NEVER runs `devbot reinit` — not in §1, not in §9, not to "refresh" state.** Reinit is a mutation of the very system under audit: it rewrites the harness tree beneath the running session, can invalidate the session's own registries (audit-45 §3 — a mid-session reinit killed the Skill tool for the rest of that session), and it makes the audit self-referential — verifying a reinit by running one. Every probe below that historically required reinit (the §1 byte-idempotency double-reinit, the §9 module add→reinit→remove loop) is recorded as **NOT-RUN** in the report with its sanctioned vehicle (the fixture launchers run `test-reinit.sh`'s double reinit in a disposable container **before the harness starts** and write `BYTE-IDEMPOTENCY-PASS/FAIL` plus per-file SHA-256 byte values to `.agents/logs/byte-idempotency.log` — in §1 **read that captured verdict** rather than recording NOT-RUN; the module flow likewise belongs in a disposable container). Do NOT run `devbot reinit`, `devbot module add/remove`, or the destructive fixture scripts (`test-reinit.sh`, `test-oc.sh`, `test-cc.sh`) — those mutate or destroy the tree being audited.

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

| Aspect                | Container                                                                                                                         | Host                  |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Project dir           | a bind mount (e.g. `/app`) of the host tree                                                                                       | the real directory    |
| dev-bot install       | under the container home (e.g. `/home/ubuntu/.local/share/dev-bot`)                                                               | under the user's home |
| Docker daemon         | absent (MCP wrappers fall back to npx/direct)                                                                                     | present               |
| GPU                   | via passthrough (`--gpus all`, `/dev/nvidia*`) — `nvidia-smi` visible                                                             | native                |
| Shared state dirs     | host-mounted (`~/.local/share/opencode`, `~/.cache/{qmd,opencode,bun}`, `~/.npm`) — persist across containers                     | native                |
| Host-side paths       | expected to be **invisible inside the container** (e.g. the value of `JETBRAINS_PROJECT_PATH`, any `/home/<user>/...` in configs) | expected to exist     |
| Container-local state | does NOT persist (ephemeral container) — e.g. caches, the install, fixes made in-session                                          | persists              |

**Rules of thumb** (prevent the recurring misdiagnoses):

- A config value that is a host path (`/home/...`) missing inside a container is **expected by design** when it exists to route a host-side service (e.g. jetbrains) — do not flag it; verify the launching env sets it correctly instead (see the jetbrains rule in §4).
- A symlink/cache pointing at the container's install path (`/home/ubuntu/.local/share/dev-bot/...`) that dangles on the host is a **host-side artifact of a container-materialized tree**, not a wiring defect.
- Docker-absent behavior (npx fallbacks, "no docker daemon" skips, container round-trips N-A) is **correct inside a container**.
- GPU verdicts are judged the same in both (the GPU is visible via passthrough), but the ollama container and qmd/opencode installs live on the **host** — inside a container you are auditing the host's services through the network.

## 0b. Detect the harness(es)

First determine which agent harness(es) are wired and which one you are running under, because the MCP config file and tool-naming convention differ per harness.

- **Which harnesses are enabled** — check the `modules` map in `.devbot.project.jsonc` and `.devbot.global.jsonc`: a harness is enabled unless its key (`opencode` or `claudecode`) is present and `false`; absent = enabled. A project may have **both** enabled, in which case both `.opencode/` and `.claude/` exist and both config files are wired. If neither dir exists, `devbot reinit`'s harness step did not run — record that as a FAIL.
- **Which harness you are running under** — look at your own tool palette naming: opencode exposes MCP tools as `<server>_<tool>` (e.g. `devbot-tools_*`, `graphify_*`); claudecode exposes them as `mcp__<server>__<tool>` (e.g. `mcp__devbot-tools__*`, `mcp__graphify__*`). Cross-check with the `harness` key (single value, picks the launch binary) if present.
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
- **Reinit byte-idempotency (audit-32 NOTE, fixed audit-33) — read the captured launcher verdict; NOT-RUN only when absent.** Live verification would require running `devbot reinit` twice and byte-comparing the generated files (`.devbot.project.jsonc`, `AGENTS.md`, `CLAUDE.md`, `opencode.jsonc`, `.mcp.json`) — the audit never runs reinit (mandate), so do not snapshot-and-reinit in place. Verify instead: (a) **captured launcher verdict FIRST** — the fixture launcher runs the double reinit BEFORE the harness starts and writes the verdict plus per-file SHA-256 byte values to `.agents/logs/byte-idempotency.log` (rotated into `.agents/logs/rotated/` as `*byte-idempotency*.log` at harness start when `start.sh` runs). If present, report **PASS/FAIL** and cite the captured per-file byte values — **FAIL** when the marker line is `BYTE-IDEMPOTENCY-FAIL`, **PASS** when `BYTE-IDEMPOTENCY-PASS`. Record **NOT-RUN** (with the static evidence in (b)) only when no captured verdict file exists; (b) **static** — the idempotency guards are present in the audited revision: `remove_mcp_key.py` is text-surgical (string/comment-aware entry removal, no whole-file rewrite), `mcp_key_is_current.py` skips removal of MCP keys that already match their module templates, the graphify AGENTS.md removal strips its trailing blank, and reset.sh no longer churns current keys. Historic drift causes (all fixed, for static recognition): `remove_mcp_key.py`'s whole-file `json.dump` rewrite expanded compact objects and dropped comments on every reset; the graphify `## graphify` section removal left a trailing blank in AGENTS.md; and reset.sh churned MCP keys that already matched their module templates, reordering the mcp map.

## 2. Hooks (manifest-driven)

- Edit a `.md` file and confirm the format-md hook reformats it.
- Edit a `.json`/`.jsonc` and a `.yml` file — confirm format-json / format-yml fire.
  - **Burst-edit probe (audit-32 FAIL, fixed audit-33)**: write + edit the same `.yml` within ~1s and confirm the file is NOT corrupted. The opencode adapter previously ran one format hook per `file.edited` with no per-file serialization, so two concurrent prettier runs interleaved their read-modify-writes and mixed 2/4-space indentation (a second, non-raced probe behaved correctly). `on-hooks.ts` now serializes + coalesces `file.edited` per path.
  - **Create-skip probe (opencode, audit-48 FAIL-1)**: WRITE a fresh `.yml`/`.json`/`.md` (not edit) — the format hooks must NOT reformat it on creation; the file stays exactly as written until the next edit, and a write-then-immediate-edit burst must end canonical (never mixed-indent / invalid). Root cause: format hooks fired on file _create_, silently normalizing the file before the agent's next edit; opencode's fuzzy edit tool (indentation-insensitive match) then spliced the agent's stale-indentation hunk into the normalized file, producing YAML prettier refuses to repair. The adapter now pairs each `file.edited` with its companion `file.watcher.updated` (`add`/`change`) to classify the write, and skips hooks declaring `skipOnCreate` (the three format hooks) on creates. This is **opencode-only**: claudecode's edit tool is strict (fails on mismatch) so it never produced the splice, and its format hooks still fire on Write — do NOT flag claudecode for formatting writes.
- Attempt a guarded command (e.g. `rm -rf /tmp/x`) and confirm the guards hook blocks it.
  - **Live enforcement (audit-32 FAIL, fixed audit-33)**: this must be tested LIVE on opencode — the engine CLI alone is not enough. The opencode adapter previously read `process.env.DEVBOT_ROOT` (never exported — the harness exports `DEV_BOT_ROOT`), so `--global-config ""` merged no rules and `rm -rf`/`sudo` ran unblocked even though `guards.ts` alone returned `blocked:true`. The adapter now resolves the global config from its own root (the realpath already used for manifest loading), falling back to the env var.
- If a K8s manifest is present, edit it and confirm lint-k8s fires.
- **Shell data access — session id and agent name (repeat per enabled harness).** Per-session artefacts must be able to name the session they belong to: `devbot:grade-tools` stamps every row with `$DEV_BOT_SESSION_ID` and `$DEV_BOT_AGENT_NAME`. Neither is built into either harness — both are injected — so verify the **bash channel** actually receives them: `echo "SESSION=[${DEV_BOT_SESSION_ID:-<unset>}] AGENT=[${DEV_BOT_AGENT_NAME:-<unset>}]"`. Both must be non-empty, and `AGENT` must name the agent you are actually running as (§0c); record the literal echoed values as the evidence. The same finding appears from the consumer side as `WARN: DEV_BOT_AGENT_NAME is not set` (or `DEV_BOT_SESSION_ID`) from `record-grades.py`, and as `unknown` in the `actor` column of `.agents/logs/tools-grades.csv`.

  **Mechanism, so an empty value is diagnosable:**

  | Harness    | How it is injected                                                                                                                                                                                | Look here when it is empty                                                                                                                              |
  | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | opencode   | the `shell.env` hook calls `sessionEnvVars()` (`src/harnesses/opencode/on-hooks-utils.ts`); the agent name is cached from `chat.params`, the only hook whose input carries `agent`                | `on-hooks.ts` must subscribe both `shell.env` and `chat.params`. The plugin loads at harness start, so a hook change needs a **restart** to take effect |
  | claudecode | a hook writes the assignments to `$CLAUDE_ENV_FILE`, which Claude Code runs as a preamble before every Bash command. Claude Code sets **no** session-id env var of its own (upstream issue 47018) | `hooks.json` must register the `SessionStart` and `PreToolUse(Bash)` handlers, and `$CLAUDE_ENV_FILE` must be exported to the hook process              |

  **Not defects:** the values reach the **bash tool only** — a PTY session does not inherit them (`devbot:shell-strategy`), so probe through bash, never a PTY. Inside a subagent the session id is the subagent's **own** session (a child of the primary's), which is by design: each actor grades its own slice, so seeing a different id per agent is correct. On claudecode the agent name is written from a tool-event payload and the docs do not guarantee Claude Code regenerates the Bash preamble _after_ the hook runs, so the first command of a session may still read the previous value — re-echo on a later command before reporting a mismatch.

## 3. Skills

- Trigger skills by intent and confirm they load — e.g. git commit guidance → `devbot:git-conventional-commits`, a small change → `test-driven-development`, project exploration → `devbot:create-project-report`.
- **Session-variance rule (claudecode)** — a claudecode audit at revision `d5f61e4e` (audit-50) could not resolve ANY project skill via the Skill tool (`Unknown skill` for all 93 wired dirs) while global (`~/.claude/skills`) and bundled skills loaded; an earlier claudecode audit at revision `2c22bd91` (audit-47) loaded project skills fine — with **zero commits touching `src/harnesses/claudecode/` between those revisions**. Same flatten layout, different outcomes ⇒ the cause is session/harness-environment variance, not the flatten code. When every project skill fails while global/bundled load: (a) verify the session's project root is actually the fixture (how the harness launched `claude` — cwd/`--add-dir`) — project-level `.claude/skills` only loads for the session's project, which would also explain "only global skills reachable"; (b) confirm `.claude/skills` was materialized before session start (Claude Code does not hot-load new skill dirs created mid-session — documented, not a dev-bot defect; a mid-session `devbot reinit` also historically killed the Skill registry — audit-45 §3 — which is one reason this audit never reinits); (c) the decisive test is a **guaranteed-fresh** session (launched strictly after a completed reinit) — flag a discovery defect only if project skills still fail there. Do NOT flag the flatten layout on a single session's evidence.

## 4. Tools (MCP palette)

- Invoke tools directly (e.g. `search-memories`, `devbot:git-report`, `devbot:tree`, `devbot:format-md`) and confirm each returns output.
- Confirm the `devbot-tools` MCP tools are discoverable and return `mcp-meta` correctly.
- **MCP server health** — a registered-but-unconnected MCP server is a FAIL. Repeat this block per enabled harness.
- **Intentionally-disabled servers are N/A, not FAIL.** An entry carrying `enabled: false` is shipped wired-but-off by design (see [MCP configuration](/mcp-config#per-server-enablement)) — record it as N/A. Only an entry that is absent-`enabled` or `enabled: true` yet has no reachable tools is a FAIL. The default-disabled servers are `chrome-devtools`, `playwright`, `signoz`, `jetbrains` and each `datasources-<name>`.
- A value in `enabled` may be the user's own switch, not the module default — read the value, never assume it matches the module's declared default.

  **opencode** — (1) Enumerate the servers from the `mcp` block in `opencode.jsonc`, reading each entry's `enabled`. (2) For each entry that is enabled — `enabled` absent or `true` — confirm its tools are reachable in your own tool palette — opencode names them `<server>_<tool>` (e.g. `devbot-tools_*`, `codebase-index_*`, `graphify_*`, `context7_*`); a server with no matching tools is not connected. An entry with `enabled: false` is intentionally off: expect no tools and report N/A. (3) Find the cause: grep the newest `~/.local/share/opencode/log/*.log` for `server unavailable` and `status=failed` — opencode logs `message="server unavailable" key=<server> type=local status=failed` when a local MCP server fails to launch (the timestamp distinguishes a launch race from a hard failure). (4) Diagnose per-server from its launch command — e.g. graphify's wrapper (`bash .opencode/graphify-serve.sh graphify-out/graph.json`) exits 0 silently when `graph.json` is absent, so a fresh `devbot reinit` often launches it before the graph is built; reloading the session recovers it.

  **jetbrains** — the `IJ_MCP_SERVER_PROJECT_PATH` header holds an **OpenCode token**, resolved at launch, not a stored path. It is `{env:PWD}` by default, or `{env:JETBRAINS_PROJECT_PATH}` when that var was set when the manifest was generated (init); the TOKEN is chosen at init, its VALUE resolves from the launching shell's env. So do NOT expect a host path in the config — expect one of those two tokens. Verify: (a) the header is one of the two tokens; (b) when it references `JETBRAINS_PROJECT_PATH`, that var is set in the shell that launched the harness (the launch gate in `start.sh` flags it when unset — the runtime `.opencode/jetbrains.mcp.json` is scanned); (c) the server connects (tools respond). The resolved host path reaches the IDE at launch (that is the design for the host-routed IDE) but must not appear in the config file. If `get_project_modules` returns a different project than expected, that is the IDE's currently-open-project state, not a config defect.

  **claudecode** — (1) Enumerate the servers from the `mcpServers` block in `.mcp.json`. (2) For each, confirm its tools are reachable in your own tool palette — claudecode names them `mcp__<server>__<tool>` (e.g. `mcp__devbot-tools__*`, `mcp__codebase-index__*`, `mcp__graphify__*`, `mcp__context7__*`, `mcp__chrome-devtools__*`, `mcp__playwright__*`); a server with no matching tools is not connected. (3) Find the cause: claudecode logs MCP connection failures under `~/.claude/logs/` **when that directory exists**; in current Claude Code CLI builds it does not — the per-server connection logs live at `~/.cache/claude-cli-nodejs/<project-slug>/mcp-logs-<server>/*.jsonl` (one file per session, JSON lines with `error`/`debug` fields). Check both: grep for the server name plus `failed to connect` / `MCP` (the signature differs from opencode's `server unavailable`; adapt as needed). (4) Diagnose per-server from its launch command — e.g. graphify's wrapper (`bash .claude/graphify-serve.sh graphify-out/graph.json`) has the same `graph.json`-absent launch race as opencode. (5) **jetbrains**: unlike opencode, the claudecode manifest bakes the concrete `JETBRAINS_PROJECT_PATH` (host-side) at init, so the header is a literal path, not a token — a path missing inside the container is expected, not a defect; verify the init-time var was set and the server connects (see the opencode block for the token-vs-path distinction).

  Report every unavailable server in the FAIL table with the harness, the exact log line, and the likely cause.

- **GPU usage (codebase-index)** — first determine whether the environment actually has GPU access, then verify the GPU-dependent capability either uses it or correctly falls back:

  **Environment GPU** — `nvidia-smi` (or `/dev/nvidia*` for NVIDIA, `/dev/dri/renderD*` for Intel/AMD). Record present/absent and the driver version. This is the ground truth everything below is judged against.

  **qmd** — no GPU check: qmd is BM25-only (no model, no embeddings — ADR `20260913072905-qmd-bm25-only-no-model-downloads`). Do not look for GGUF models, `qmd doctor` device lines, or GPU config for qmd.

  **codebase-index** — embeddings go through ollama. (1) Read the provider config (`.opencode/codebase-index.json` — `customProvider.baseUrl` / `embeddingProvider`). (2) Check the ollama API (`curl <baseUrl>/api/tags` — is the embedding model present?). (3) Check whether the serving ollama uses the GPU — `curl <baseUrl>/api/ps` shows running models with VRAM usage (`size_vram` > 0 = on GPU), or `nvidia-smi` shows an ollama process with memory. Cross-check:
  - GPU **present** → the embedding model should be served with GPU acceleration. FAIL if ollama runs it CPU-only while a GPU is available and usable (report `api/ps` or `nvidia-smi` evidence).
  - GPU **absent** → ollama runs CPU — acceptable; FAIL only if it attempts GPU and fails.

  Report every mismatch in the FAIL table with the config value, the runtime evidence, and the likely cause.

## 5. Memory

**Vault cold-start protocol (audit-41 FAIL-3).** On a fresh reinit — or a harness launched directly (bare `opencode`/`claude`, bypassing `devbot` start.sh's detached prune warm-up) — the project memory vault starts **cold**: the `app` collection shows 0 files / "updated never" until the first edit under `/memory/latent` fires the reindex hook, or an explicit `reindex-memories` runs. It then takes a few minutes to warm up (the reindex runs `qmd update` / `mdctx build` in the background). **Cold-at-start is expected, not a FAIL.**

- **Ordering — check the vault LAST.** The checks below that depend on vault warmth (collection state, marker search, delete→prune re-search) are the **last capability checks of the audit**: run §6–§9 first, then return to them, so the audit's own elapsed time and probe writes have had minutes to warm the vault. If you must write the §5 probe note earlier (its `file.edited` is what triggers the warm-up reindex), do so — but defer the _verification reads_ to the end.
- **Retry before FAILing.** If a warmth-dependent check still fails at the end (e.g. `app` still 0 files / "updated never", or the probe marker is not found): trigger an explicit `reindex-memories` (full — or `prune` for the delete→prune check), wait a few minutes, and re-check. Only record a FAIL if the collection is still cold after the warm-up trigger plus retry.

Then run the checks below; they verify the vault _works_ once warm:

- **Passive-memory round-trip**: write a note under `.agents/memory/latent/learnings/` with a unique marker (e.g. `devbot-audit-probe-<timestamp>`) and a distinctive phrase, then run `search-memories` for that phrase and confirm the note is returned. This verifies the write → passive reindex → search round-trip. If it isn't found immediately, the passive reindex (`qmd update` / `mdctx build`) may still be running in the background — run `qmd update` (or wait) and re-search.
- **Project memories — explicitly verify**: run `search-memories` for a phrase that exists only in the **project** vault (`.agents/memory/latent/`) and confirm the result's file path is under the project vault — not the global store. This proves the project collection is registered and searchable. (If the project vault has no seeded content yet, write the probe note above first, then search for its marker.)
- **Global memories — explicitly verify**: run `search-memories` for a phrase that exists only in the **global** store (`storage/global-memories/` — the shipped knowledge base symlinked as `.agents/memory/latent/global`) and confirm the result's file path is under `global/` (or the global collection `dev-bot-global`), not the project vault. This proves the `latent/global` symlink and the `dev-bot-global` QMD collection are wired. Good probe phrases: a distinctive tech-gotcha keyword that only lives in the global store — e.g. search a term from a `storage/global-memories/<tech>/` filename you can see exists. If `search-memories` returns nothing for a global-only phrase, record the mismatch — the tool's global-collection wiring is broken.
- **Both must return results**: the audit must show evidence of at least one project-vault hit AND at least one global-store hit. A memory section that only verified one of the two stores is incomplete — record which store was not proven searchable as a FAIL (the `latent/global` symlink, the `dev-bot-global` collection registration, or the search tool's collection wiring may be broken).
- **Concurrent-process races in the logs**: when scanning `hooks.log`, `memory-index.log` and the reindex paths, watch for signatures of two processes racing the same resource — `SQLITE_CONSTRAINT` / `constraint failed`, `SQLITE_BUSY` / `database is locked`, primary-key collisions, "already running", or duplicate background jobs stacking. A single file edit firing several hooks at once is normal; it must be safe (coalescing locks, pidfiles, upserts). FAIL if the logs show such race signatures or a hook/tool that can be invoked concurrently runs its work unguarded.
- **Delete → prune self-heal (live — audit-28/29 FAIL, fixed audit-30; mechanism moved to start.sh in audit-36)**: deleting a memory note must stop it surfacing in search. Write a probe note (as in the round-trip above), wait until `search-memories` returns it, then `rm` it. Neither harness delivers a delete event for external (bash) deletions — opencode 1.18.26 emits no watcher unlink and claudecode has no delete event — so the self-heal runs **at launch**: `devbot` start.sh fires a detached `reindex-memories prune` (`qmd cleanup && qmd update`, no embed — under the mdctx engine an incremental build of the project + global indexes) before the harness boots, logging a `[reindex-memories-prune-start]` marker plus the tool's `{"status":"started",...}` JSON to `.agents/logs/memory-index.log`. Cross-check that log for the marker. FAIL if the stale entry persists after a fresh `devbot`-launched session with no marker (prune not fired). A note deleted mid-session may briefly surface until the next launch — expected, not a defect. NOTE: a harness launched directly (bare `opencode`/`claude`, bypassing start.sh) does not fire the prune — `devbot` is the canonical launch path.
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

At the end, examine the runtime logs for issues that no live tool call would surface. First determine which harness(es) are enabled (section 0: the `modules` map in `.devbot.project.jsonc` / `.devbot.global.jsonc` — a harness is enabled unless its key is `false`). To know which harness you are currently running under, look at your own tool palette naming: opencode exposes MCP tools as `<server>_<tool>` (e.g. `devbot-tools_*`, `graphify_*`); claudecode exposes them as `mcp__<server>__<tool>` (e.g. `mcp__devbot-tools__*`, `mcp__graphify__*`) — cross-check with the `harness` key (single value, picks the launch binary) in the configs. Then examine the logs in this order:

### 8a. Project MCP logs — `.agents/logs/` (shared by all harnesses)

The devbot dir's MCP server logs. Enumerate `*.log` files, then inspect each for error signatures. Known healthy signatures to distinguish from real issues: the `devbot-tools-mcp.log` `discovered N tool(s)` line, the `chrome-devtools-mcp.log` startup banner, empty `graphify-mcp.log` / `playwright-mcp.log`, and stray terminal escape sequences (e.g. `[?25h`) in some logs. A server that ships disabled by default (`enabled: false`) writes no log at all — an absent `chrome-devtools-mcp.log` / `playwright-mcp.log` is expected, not a missing-log finding. Real issues look like stack traces, `error`/`failed`/`fatal` lines, or crash loops (a log growing unboundedly with restarts). Report anything that is not a known-healthy signature.

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

External modules are the one dev-bot feature with a registration CLI (`devbot module add`) plus a separate wiring pass (reinit's `external-modules/init.sh`). Audit what is verifiable **read-only**; the state-mutating end-to-end loop is NOT-RUN in-audit (it requires `devbot reinit` and `.devbot.global.jsonc` edits — both prohibited by the mandate).

- **Inventory** — list every entry under `external_modules` in `.devbot.global.jsonc` (both modules declared by internal `external-modules.json` files and user/CLI `module add` entries). For each confirm: the source resolves (vendor clone for `url`, existing dir for `local_path`); it is wired as `.agents/<type>/<name>` per its `paths` map in the project's devbot dir; and its storage mirror exists under `storage/external-agentic-modules/<name>/`. Also confirm the wiring matches the declared-module gate: a module declared by a **disabled** umbrella module is skipped entirely — not cloned, mirrored, or wired (audit-03 §9) — and any mirror it left from an earlier state is pruned on reinit; that is the design, not a FAIL.
- **Install all external modules** — `devbot module install` git-pulls the vendor clones (a mutation of the install's vendor tree). Under the no-modify mandate this is **NOT-RUN** unless the mandate explicitly permits install-state updates; verify statically that every `url` entry has a resolvable clone and every `local_path` entry an existing dir instead.
- **`devbot module list`** — run it and confirm each entry's status reflects that module's own storage mirror (✔ mirrored, ✖ not) rather than the shared vendor clone — so a module declared by a disabled umbrella correctly renders ✖ (audit-03 §9). Read-only.
- **Local-path module end-to-end (audit-29 FAIL-1) — NOT-RUN in-audit.** This flow is `devbot module add <dir>` (a `.devbot.global.jsonc` config edit) → `devbot reinit` (wires `.agents/<type>/<name>` + storage mirror) → verify → `devbot module remove` → reinit — the audit never runs reinit or edits config (mandate). The sanctioned vehicle is a **disposable container**: create a dummy local module, `module add` → `reinit` → verify the wiring + mirror → `module remove` → cleanup + `reinit`, and confirm the fixture is back to its pre-test state (no dummy references, no broken symlinks). Record NOT-RUN with this vehicle; do NOT register or remove modules in the audited project.

Fold any finding into the FAIL table with the config entry, the observed wiring state, and the likely cause (declaration gate in `external-modules/init.sh`, `_discover_projects()` scope, `_unwire_module` coverage, etc.).

## 10. Docker services — containers running with their real mounts

Dev-bot's shared MCP gateways (`codebase-memory`, `mdctx`, `signoz`, `svelte`, plus `ollama`/`litellm` when enabled) are one container per enabled module, all in the compose project `devbot` with a fixed `dev-bot-*` name. **A gateway can be "up" and still be useless**, and it fails silently in both ways that matter:

- **A dead server inside a live container.** Every bridged gateway runs `mcp-proxy` in the foreground, so it exits when its stdio child dies — but a container can still be Up while the capability is already gone; the module's `up.sh` reports `gateway not reachable … after 30s — MCP server will be unavailable` and the harness starts without it. Never infer the capability from `docker ps`.
- **A mounted volume that is not the volume you meant.** Compose creates a **missing bind-mount source** on the host as `root:root`. A module service that runs as the host uid then finds its own state dir owned by root and refuses to start — `exact executable identity could not be verified (cache-private) - <dir>: owner uid 0, expected euid <uid>` — or silently cannot write its index. The mount _path_ in `docker inspect` still looks correct; only the host-side owner reveals the substitution. `bin/up.sh`'s `_ensure_writable_bind_sources` pre-creates the writable sources as the host user before compose runs — a root-owned writable source means that pre-create did not run.

**Inside a container this whole section is N-A** — there is no docker daemon (§0), so record N-A with that evidence rather than FAIL.

For every service the enabled modules declare:

- **Enumerate what SHOULD be running** — `docker compose -f <each selected compose> config --services` (read-only), or the services named in each enabled module's `docker-compose.yml`. One service per enabled module; a service absent from that list is not expected, and an expected service with no container is a FAIL.
- **Running, not exited, not restart-looping** — `docker ps -a --filter label=com.docker.compose.project=devbot --format '{{.Names}}\t{{.Status}}'`, then per container `docker inspect --format '{{.State.Status}} exit={{.State.ExitCode}} restarts={{.RestartCount}}' <name>`. `restart: "no"` is deliberate (a gateway must not come back after a reboot without `devbot up`), so a stopped container is a FAIL, not a shrug. Cite `docker logs --tail 30 <name>` — a bridge logs its child's stderr there, which is where the ownership error above surfaces.
- **The declared healthcheck, not just the process** — `docker inspect --format '{{json .State.Health}}' <name>`. The gateways declare a real MCP-handshake healthcheck, so `unhealthy` is a FAIL even while `Status=running`; no `Health` key means the service declares none — a NOTE only.
- **The gateway answers a real MCP call** — POST an `initialize` to the module's own endpoint from its `mcp.json` (mdctx `:18501`, signoz `:18502`, svelte `:18503`, codebase-memory `:18504`, each `http://127.0.0.1:<port>/mcp`) and confirm `200`, then make one **real tool call** (`tools/list` or the module's own tool). The handshake proves only the transport: `mcp-proxy` forwards just `HOME`/`PATH` to its child unless `--pass-environment` is given, so a bridge that lost its environment answers the handshake and then reads the wrong root.
- **Runs as the host uid, not root** — the _effective_ uid must be the host uid; root is a FAIL (it leaves root-owned files in shared stores the host tools can no longer rewrite). For a service that sets `user:` (mdctx) `docker inspect --format '{{.Config.User}}' <name>` shows it directly. codebase-memory deliberately leaves `Config.User` empty — its entrypoint starts as root, chowns the store, then drops with `setpriv` — so check the running process instead: `docker exec <name> sh -c 'grep ^Uid: /proc/1/status'` must show `$(id -u)`. Because that `Config.User` is empty, a bare `docker exec` there lands as root: expected, not a finding.
- **Every bind mount: the source exists on the host, is a directory, and is owned by the host user** — take the expected sources from the module compose (or `docker compose … config --format json`) and compare against `docker inspect --format '{{json .Mounts}}' <name>` (source, target, `RW`/`ro`). The sources in play are `<devbot>/storage/.mdctx`, `<devbot>/storage/global-memories` and `$HOME` (codebase-memory's repo root); check each with `ls -ld` **on the host** — owned by `root` is the substitution signature above. Then confirm the source is **not empty**: a gateway mounted on an empty directory starts, answers, and returns nothing.
- **The codebase-memory store is a named volume, not a bind mount** — its index lives on `devbot-codebase-memory-store` (mounted at `/srv/cbm`), so it never appears in the bind-mount sweep above and has no host owner to check. Confirm it with `docker volume inspect devbot-codebase-memory-store`; a gateway that starts but returns no projects usually has an empty or freshly-created volume.
- **ro stays ro, rw stays rw** — mdctx's corpus (`storage/global-memories`) and codebase-memory's repo root are declared `read_only: true` together with `create_host_path: false`; the index store (`storage/.mdctx`) must be **rw**, since the server rewrites it. A corpus mounted rw, or a store mounted ro, is a FAIL. Because those ro mounts refuse to create their own source, an empty or root-owned ro source is itself a FAIL — not "a volume compose helpfully made for me".
- **`devbot up`'s own verdict** — when `bin/up.sh` cannot bring compose up it prints `docker compose up failed — docker services not started` and returns 1, aborting the start; a source the daemon refused to create (`create_host_path: false`) surfaces there. Attribute a §10 FAIL to its real cause: the module `up.sh` "gateway not reachable" warning that follows is the consequence, never the cause.

## Report

At the end, produce an audit that answers only these two questions (project specifics are irrelevant):

1. **Did `devbot reinit` set things up correctly?** — lifecycle scripts, module wiring, harness adapters, MCP registration.
2. **Can the local agent use all dev-bot capabilities?** — skills, tools, hooks, commands, memory, agents.

### Write the report to a file

Write a markdown report to `.agents/memory/thinking/devbot-audit-NN.md` (`.agents` is the devbot dir from config), where `NN` is the next sequential integer starting at `01` — first list the existing `devbot-audit-*.md` files in that directory, then use the next number (e.g. `01` if none exist, `02` after `01`, …).

**Open the report with a header block** stating the audit context — every report MUST begin with these four lines before any findings (they let a reader interpret the whole report without re-deriving the environment):

- **ENVIRONMENT: container** or **ENVIRONMENT: host** — plus the evidence (from §0).
- **HARNESS(ES) ENABLED** and **HARNESS THIS AUDIT RAN UNDER** — which harness(es) are wired (`modules` map) and which one this session used (tool-palette naming), plus the evidence (from §0b). If both harnesses are enabled, the audit covers both — say so, and attribute every FAIL/NOTE below to a specific harness.
- **RUNNING AGENT** — `DevBot` (or the FAIL if not, per §0c).
- **DEVBOT REVISION (audited commit)** — the exact dev-bot install revision this audit ran against, plus the audit date. Audits 38–41 omitted it and their FAILs turned out to describe pre-fix code from an older install — without the revision a reader cannot tell whether a finding applies to the code in front of them. Resolve it from the dev-bot **install** (the tree the harness symlinks resolve to), not the project: `git -C <install-root> rev-parse HEAD` (+ `git -C <install-root> log -1 --format=%cd --date=short` for the commit date), where `<install-root>` is the install path from §0 (container: e.g. `/home/ubuntu/.local/share/dev-bot`; host: e.g. `~/.local/share/dev-bot`). If the install is not a git checkout, say so explicitly and give the best version marker available (install path + directory mtime).

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
