---
date: 2026-09-04
keywords: ["devbot", "audit", "skipOnCreate", "file.watcher.updated", "createKindResolver"]
---

# audit 47–50 fix session: format create-skip, lint-k8s sweep scope, read-only audit

Fixes from the audit-47/48 (committed `b53d5fd2`…`d5f61e4e`) and audit-49/50
(`31be7ed2`…`818e5a51`) reports on `feature/mac-fixes-local-external-modules`.
Mechanisms and non-obvious mechanics so future audits re-verify the fixed
behavior instead of re-flagging stale symptoms.

## opencode format-on-create corruption (audit-48 FAIL-1) → `skipOnCreate`

opencode's `write`/`edit`/`apply_patch` tools publish `file.edited` (payload
only `{file}` — no create-vs-edit flag) AND a companion `file.watcher.updated`
with `event: "add" | "change"`. The adapter dispatched content hooks on every
`file.edited`, so a file _create_ was silently prettier-normalized before the
agent's next Edit. opencode's edit tool matches indentation-insensitively via
~9 fuzzy replacers (`IndentationFlexibleReplacer`, `LineTrimmedReplacer`, …),
so the agent's stale-indentation hunk was spliced into the normalized file →
mixed 2/4-space YAML that prettier refuses to repair (corruption persisted).

Fix: `createKindResolver()` in `src/harnesses/opencode/on-hooks-utils.ts`
pairs each `file.edited` with its companion watcher event — 250 ms settle
timeout falls back to "change" (dispatch) so opencode versions that publish
only `file.edited` keep working; out-of-order watcher-before-edited is
remembered 500 ms and consumed. Hooks opt out of creates with the manifest key
`skipOnCreate: true` (the three format hooks). Per-hook, not blanket:
lint-k8s and the memory-reindex hooks leave it unset and still fire on creates
(a fresh latent note must be indexed — the passive-memory round-trip depends
on it). claudecode unchanged: its strict edit tool never spliced, and its
format hooks still fire on Write (documented in audit.md so auditors don't
flag the harness difference).

**Native opencode formatters do NOT fix this class** (evaluated and rejected):
they also normalize on create (in-tool, invisible to the agent's model) and
refuse to repair the mixed-indent result, so the adversarial write→edit probe
still fails. Skip-on-create is the only dev-bot-side fix that passes it.

## lint-k8s directory sweep scope (audit-48 N5)

A directory sweep gathered every `.yml/.yaml/.json` and kubeconform-validated
each as a manifest → every non-manifest (config files, `.opencode/index`
caches, `graphify-out`) reported `missing 'kind' key`. Sweeps now content-gate
via `_is_manifest` (contains an `apiVersion` key AND a `kind` key — the same
heuristic as the hook content-gate, tolerating JSON quoting); an explicitly
passed non-manifest file is still linted loudly.

## search-memories `--query` two-token (audit-49 NOTE-1)

`search-memories.mcp.sh` forwarded a literal `--query` into EXTRA_ARGS with no
value → argparse `expected one argument`. It now treats `--query` as a
two-token flag (value consumed) and `--query=…` as pass-through, mirroring
`--collection`/`--max-results`.

## reindex-memories background logging + errexit pid leak (audit-49 NOTE-2)

The background job redirected qmd output to /dev/null with no completion
marker → a slow/failed reindex was unobservable (audit-49 watched ~10 min of
silence with the `app` collection count churning). The job now logs
start/finished markers with per-step exit codes to the project's
`.agents/logs/qmd-index.log` (cwd-derived when `.agents` exists, else the
devbot cache log). Latent bug fixed in the same edit: the subshell inherited
the tool's `set -e`, so a failing `qmd cleanup` aborted it BEFORE the pid-file
`rm` — leaking the pid and wedging the tool into perpetual `in_progress`. The
job now runs `set +e`, records exit codes, always removes the pid file.

## Audit session variance (audit-50 claudecode skills FAIL)

claudecode audit-50 could not resolve ANY project skill via the Skill tool
(`Unknown skill` for all 93 wired dirs) while global (`~/.claude/skills`) and
bundled skills loaded. Audit-47 (claudecode, same flatten code) loaded them
fine — **zero commits touched `src/harnesses/claudecode/` between the two
revisions** (`2c22bd91` → `d5f61e4e`). Same layout, different outcome ⇒
session/harness-environment variance, NOT a flatten defect. Do not flag the
flatten layout on single-session evidence; diagnose by verifying the session's
project root, that `.claude/skills` predates session start, and with a
guaranteed-fresh-session probe. A mid-session `devbot reinit` historically
kills the CC Skill registry for the rest of the session (audit-45 §3) — one
reason the audit never reinits.

## Audit command is now strictly read-only (stakeholder decision)

`audit.md`'s mandate already said "no reinit" but §1 (byte-idempotency) and §9
(module e2e) instructed the auditor to run it, so audits split: 48/49
read-only (probes NOT-RUN), 47/50 reinit-ing repeatedly (audit-50 reinit-ed
3× mid-session). Now: an unconditional never-reinit rule, and every
reinit-based probe is NOT-RUN with a sanctioned launcher vehicle
(`test-reinit.sh` prints `BYTE-IDEMPOTENCY-PASS/FAIL` in a disposable
container; the module add→reinit→remove loop likewise). See the PDR.
