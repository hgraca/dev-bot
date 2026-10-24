---
name: devbot:notion
description: "Use when reading or writing Notion through the Notion MCP server — search the workspace, fetch page or database content, create and update pages and databases, read and post comments. Triggers on 'notion.so', 'Notion page', 'Notion database', 'Notion workspace'."
---

# Notion — official hosted MCP server

The `notion` module wires Notion's **official hosted MCP server**
(`https://mcp.notion.com/mcp`, Streamable HTTP) — the server Notion builds and
maintains, so the tool surface tracks their releases rather than a dev-bot copy.
The open-source `notion-mcp-server` package is no longer actively maintained; do
not fall back to it.

The module is opt-in and its server ships **disabled** (`enabled: false` in the
module's `mcp.json`); enabling the module links this skill but leaves the server
off. Turn the server on per harness:

- **opencode** — set `mcp.notion.enabled` to `true` in the generated
  `opencode.jsonc` and restart (opencode reads its config once at startup).
- **Claude Code** — a disabled server is omitted from `.mcp.json`, so set
  `enabled: true` in the module's `mcp.json` and run `devbot reinit`; or add it at
  user scope with
  `claude mcp add --scope user --transport http notion https://mcp.notion.com/mcp`.

## Authentication

The server authorizes with **OAuth** (authorization code with PKCE). opencode
detects the server's 401 and runs the consent flow itself, so authenticate once
per machine:

```sh
opencode mcp auth notion
```

Tokens live with the host, never in the project config, and are scoped to the
workspace and pages the user consented to. In Claude Code, run `/mcp` and follow
the browser flow. If a call is rejected as unauthorized, re-run the flow.

**Non-interactive alternative** (CI, service accounts) — Business and Enterprise
plans only: a workspace owner creates an MCP token in the Notion developer
portal, and the client sends it as a bearer token. Add `"oauth": false` and pass
the credential through `headers`, reading the token from the environment so no
secret reaches the config:

```json
{
  "mcp": {
    "notion": {
      "type": "http",
      "url": "https://mcp.notion.com/mcp",
      "oauth": false,
      "headers": { "Authorization": "Bearer {env:NOTION_MCP_TOKEN}" }
    }
  }
}
```

A **header** value may embed `{env:VAR}` (the translator rewrites it to
`${VAR}` for Claude Code), unlike an `env` value, which must be the whole value;
`devbot init` warns when a referenced variable is unset. Prefer OAuth for
interactive use.

## Discover access before calling

Two calls orient you in a new session:

1. `notion-get-self` — identifies the connected workspace and user.
2. `notion-get-tool-access` — lists the tools this connection may use and, under
   `restricted_parameters`, the plan-gated search options. Workspace-owned
   connections expose only the tools an admin selected. A plan-gated filter or
   sort does not fail the call: Notion drops it, runs the rest, and adds a
   `notices` array naming the dropped fields.

Do not assume tool names from another Notion integration. The hosted server uses
hyphenated `notion-*` names; treat the access map as the contract. A tool absent
from `tools/list` is available only when it is the legacy `notion-ai-search`
(named directly in the read path below); an unselected tool on a workspace-owned
connection is not callable.

## Read path

1. **Search** — `notion-search` with short, specific keywords or a page title
   (up to 50 results, with filters for location, creator or editor, date, title,
   and content status). For connected sources (Slack, Drive, …) call
   `notion-connector-search` alongside it, when the session lists that tool.
   `notion-ai-search` is the legacy natural-language variant: it does not appear
   in `tools/list` but stays callable by name, and it needs AI search on the
   workspace — prefer the pair above. All three accept `query_type: "user"` to
   resolve a person by name or email.
2. **Fetch** — `notion-fetch` by URL or ID returns a page, database, or data
   source, including a database's schema and templates. When `truncated` is
   `true`, re-fetch each id from `unknown_block_ids` to read the omitted
   subtrees. An `object_not_found` on a known id usually means the page is not
   shared with the connection — ask the user to share it rather than retrying.
3. **Query databases** — `notion-query-data-sources` runs SQL (filters, sorts,
   aggregates) over a data source; `notion-query-multiple-data-sources` joins
   several (Business or Enterprise with Notion AI, 2–100 data sources). Fetch
   the schema first so column names are real.
4. **Comments** — `notion-get-comments` reads the discussion on a page.

Paginate and narrow a search rather than fetching whole workspaces.

## Write path — propose, confirm, act

Notion writes are visible to everyone the page is shared with. Never mutate
silently.

- **Create a page** — `notion-create-pages`, one or more per call. A shared page
  needs a parent: pass the page or database id, or `{"teamspace_id": "…"}` for a
  teamspace root. With no destination named by the user, use
  `creation_mode: "draft"` (private, workspace-level, no parent). `content` is
  Markdown; content too large or too heavily formatted fails with
  `validation_error` and creates nothing, so split it across calls or child
  pages. `allow_async: true` returns a task id to poll with
  `notion-get-async-task`.
- **Update a page** — `notion-update-page` with `update_properties` for property
  values, or `update_content` with `old_str`/`new_str` search-and-replace
  operations. Each `old_str` must match exactly once (or set
  `replace_all_matches: true`); operations that miss are skipped and reported,
  and if none of the content-changing operations match, the call returns a
  `validation_error` and leaves the page unchanged.
- **Create a database** — `notion-create-database` from SQL DDL or a typed
  template; change an existing schema with `notion-update-data-source`.
- **Comment** — `notion-create-comment` on a page or a specific block.
- **Move or delete** — `notion-move-pages`; `notion-delete-pages` and
  `notion-delete-databases` move to Trash (reversible with
  `notion-restore-pages`). A destructive call needs `user_confirmed: true` after
  the user has approved the exact list.
- **Confirm before acting** — show the target, the field, and the old → new
  value, and get approval before any create, update, schema change, move, or
  delete.
- **Never bulk-edit** without an explicit instruction naming the pages.
- **Read the result** — a write returns the property keys it actually saved and a
  `warnings` array when it repaired or dropped part of the input. Report warnings
  instead of assuming the write matched the request, and reuse the returned keys
  in later calls.

## Output

- Link what you touched — `https://www.notion.so/<page-id>` — and name the
  workspace when more than one is in play.
- Summarize in prose or a table; **do not paste raw JSON** or whole page dumps.
- For a search, state the query and filters so the result is reproducible.
- Surface missing access, dropped filters, and write warnings explicitly rather
  than reporting an empty result as "nothing there".
