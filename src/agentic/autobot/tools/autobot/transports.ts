/**
 * The real edges: Jira over HTTP, GitHub through `gh`, and the agent through `opencode run`.
 *
 * Everything here is thin on purpose. The parsers that interpret process output are exported and
 * tested, and every shape that could drift (`opencode`'s event stream, `gh --json` payloads) is read
 * defensively rather than with a fixed schema.
 */

import type { SessionSummary } from "./cleanup.ts";
import type { AgentRunRequest, AgentRunResult } from "./executor.ts";
import type { GhPullRequest, GhReview, GhTransport } from "./github.ts";
import type { JiraComment, JiraTransport, RawJiraIssue } from "./jira.ts";
import { sign } from "./signature.ts";
import { STATE_FIELD_ID } from "./state.ts";

export interface CommandResult {
    code: number;
    stdout: string;
    stderr: string;
}

/** Run a child process in `cwd` and collect its output. */
export async function runCommand(
    command: string,
    args: string[],
    cwd: string,
    env?: Record<string, string>,
): Promise<CommandResult> {
    const proc = Bun.spawn([command, ...args], {
        cwd,
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
        ...(env === undefined ? {} : { env: { ...process.env, ...env } }),
    });
    const [stdout, stderr] = await Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
    ]);
    return { code: await proc.exited, stdout, stderr };
}

const SESSION_KEYS = new Set(["sessionid", "session_id", "session"]);

function collectSessionIds(
    value: unknown,
    depth: number,
    found: Set<string>,
): void {
    if (depth > 6 || value === null || typeof value !== "object") return;
    if (Array.isArray(value)) {
        for (const item of value) collectSessionIds(item, depth + 1, found);
        return;
    }
    for (const [key, item] of Object.entries(
        value as Record<string, unknown>,
    )) {
        if (typeof item === "string") {
            if (/^ses_[A-Za-z0-9]+$/.test(item)) {
                found.add(item);
            } else if (
                SESSION_KEYS.has(key.toLowerCase()) &&
                item.trim() !== ""
            ) {
                found.add(item);
            }
            continue;
        }
        collectSessionIds(item, depth + 1, found);
    }
}

/**
 * The session id out of an `opencode run --format json` stream.
 *
 * The event schema is not contractual, so this walks the JSON looking for a `ses_…` value rather than
 * depending on a field path.
 */
export function extractSessionId(output: string): string | null {
    const found = new Set<string>();
    for (const line of output.split("\n")) {
        const trimmed = line.trim();
        if (trimmed === "" || !trimmed.startsWith("{")) continue;
        try {
            collectSessionIds(JSON.parse(trimmed), 0, found);
        } catch {
            continue;
        }
    }
    const ids = [...found].filter((id) => id.startsWith("ses_"));
    return ids[0] ?? [...found][0] ?? null;
}

/** `gh pr list --json number,url,state` output. */
export function parsePullRequests(
    payload: string,
): Array<{ number: number; url: string; state: string }> {
    let parsed: unknown;
    try {
        parsed = JSON.parse(payload);
    } catch {
        return [];
    }
    if (!Array.isArray(parsed)) return [];
    const result: Array<{ number: number; url: string; state: string }> = [];
    for (const item of parsed) {
        if (item === null || typeof item !== "object") continue;
        const record = item as Record<string, unknown>;
        if (!Number.isInteger(record.number) || typeof record.url !== "string")
            continue;
        result.push({
            number: record.number as number,
            url: record.url,
            state: typeof record.state === "string" ? record.state : "OPEN",
        });
    }
    return result;
}

/** `gh pr view <n> --json reviews` output. */
export function parseReviews(payload: string): GhReview[] {
    let parsed: unknown;
    try {
        parsed = JSON.parse(payload);
    } catch {
        return [];
    }
    if (parsed === null || typeof parsed !== "object") return [];
    const raw = (parsed as Record<string, unknown>).reviews;
    if (!Array.isArray(raw)) return [];
    const reviews: GhReview[] = [];
    for (const item of raw) {
        if (item === null || typeof item !== "object") continue;
        const record = item as Record<string, unknown>;
        const author = record.author as Record<string, unknown> | undefined;
        const submittedAt =
            typeof record.submittedAt === "string" ? record.submittedAt : "";
        // Without a timestamp the review cannot be ordered against the watermark, so it is dropped
        // rather than kept and silently never processed.
        if (!/^\d{4}-\d{2}-\d{2}T/.test(submittedAt)) continue;
        reviews.push({
            id: String(record.id ?? ""),
            authorLogin: typeof author?.login === "string" ? author.login : "",
            body: typeof record.body === "string" ? record.body : "",
            submittedAt,
        });
    }
    return reviews;
}

export interface JiraCredentials {
    baseUrl: string;
    email: string;
    token: string;
}

export interface JiraClient extends JiraTransport {
    setState(issueKey: string, value: string | null): Promise<void>;
    addComment(issueKey: string, body: string): Promise<void>;
    closeIssue(issueKey: string, assigneeId?: string): Promise<boolean>;
    unassignIssue(issueKey: string): Promise<void>;
    addLabels(issueKey: string, labels: string[]): Promise<void>;
    removeLabel(issueKey: string, label: string): Promise<void>;
}

function normaliseBaseUrl(baseUrl: string): string {
    return baseUrl.replace(/\/+$/, "");
}

export function createJiraClient(
    credentials: JiraCredentials,
    stateFieldId: string = STATE_FIELD_ID,
): JiraClient {
    const base = normaliseBaseUrl(credentials.baseUrl);
    const authorization = `Basic ${Buffer.from(`${credentials.email}:${credentials.token}`).toString("base64")}`;

    async function call(
        path: string,
        init: RequestInit = {},
    ): Promise<unknown> {
        const response = await fetch(`${base}${path}`, {
            ...init,
            headers: {
                Authorization: authorization,
                Accept: "application/json",
                "Content-Type": "application/json",
                ...(init.headers ?? {}),
            },
        });
        if (!response.ok) {
            throw new Error(
                `jira ${init.method ?? "GET"} ${path} failed: ${response.status}`,
            );
        }
        const text = await response.text();
        return text === "" ? null : JSON.parse(text);
    }

    /**
     * Labels are changed with Jira's `update` operations, not by reading and rewriting the field: a
     * read-then-write would drop a concurrent add or remove made between the two calls.
     */
    async function editLabels(
        issueKey: string,
        operations: Array<Record<string, string>>,
    ): Promise<void> {
        await call(`/rest/api/2/issue/${issueKey}`, {
            method: "PUT",
            body: JSON.stringify({ update: { labels: operations } }),
        });
    }

    async function unassign(issueKey: string): Promise<void> {
        await call(`/rest/api/2/issue/${issueKey}/assignee`, {
            method: "PUT",
            body: JSON.stringify({ accountId: null }),
        });
    }

    return {
        async search(jql: string): Promise<RawJiraIssue[]> {
            const issues: RawJiraIssue[] = [];
            let startAt = 0;
            for (let page = 0; page < 20; page += 1) {
                const query = new URLSearchParams({
                    jql,
                    startAt: String(startAt),
                    maxResults: "100",
                });
                const payload = (await call(
                    `/rest/api/2/search?${query.toString()}`,
                )) as {
                    issues?: RawJiraIssue[];
                    total?: number;
                };
                const batch = payload.issues ?? [];
                issues.push(...batch);
                startAt += batch.length;
                if (batch.length === 0 || startAt >= (payload.total ?? 0))
                    break;
            }
            return issues;
        },

        async comments(issueKey: string): Promise<JiraComment[]> {
            // The endpoint is paginated; a ticket with a long history must not hide its newest comment.
            const comments: JiraComment[] = [];
            let startAt = 0;
            for (let page = 0; page < 20; page += 1) {
                const payload = (await call(
                    `/rest/api/2/issue/${issueKey}/comment?startAt=${startAt}&maxResults=100`,
                )) as {
                    comments?: Array<Record<string, unknown>>;
                    total?: number;
                };
                const batch = payload.comments ?? [];
                for (const comment of batch) {
                    const author = comment.author as
                        Record<string, unknown> | undefined;
                    comments.push({
                        id: String(comment.id ?? ""),
                        authorId:
                            typeof author?.accountId === "string"
                                ? author.accountId
                                : "",
                        body:
                            typeof comment.body === "string"
                                ? comment.body
                                : "",
                        created:
                            typeof comment.created === "string"
                                ? comment.created
                                : "",
                    });
                }
                startAt += batch.length;
                if (batch.length === 0 || startAt >= (payload.total ?? 0))
                    break;
            }
            return comments;
        },

        async setState(issueKey: string, value: string | null): Promise<void> {
            await call(`/rest/api/2/issue/${issueKey}`, {
                method: "PUT",
                body: JSON.stringify({ fields: { [stateFieldId]: value } }),
            });
        },

        async addComment(issueKey: string, body: string): Promise<void> {
            // Signed here so no call site can forget: the signature is what stops AutoBot answering itself.
            await call(`/rest/api/2/issue/${issueKey}/comment`, {
                method: "POST",
                body: JSON.stringify({ body: sign(body) }),
            });
        },

        async addLabels(issueKey: string, labels: string[]): Promise<void> {
            await editLabels(
                issueKey,
                labels.map((label) => ({ add: label })),
            );
        },

        async removeLabel(issueKey: string, label: string): Promise<void> {
            await editLabels(issueKey, [{ remove: label }]);
        },

        async closeIssue(
            issueKey: string,
            assigneeId?: string,
        ): Promise<boolean> {
            // Look up the transition before mutating anything: a workflow without a Done-named transition
            // must not leave the ticket reassigned and still open. Absence is reported, never thrown, so the
            // caller can decide not to clear the state.
            const payload = (await call(
                `/rest/api/2/issue/${issueKey}/transitions`,
            )) as {
                transitions?: Array<{ id?: string; name?: string }>;
            };
            const done = (payload.transitions ?? []).find(
                (transition) =>
                    (transition.name ?? "").toLowerCase() === "done",
            );
            if (!done?.id) return false;

            if (assigneeId) {
                await call(`/rest/api/2/issue/${issueKey}/assignee`, {
                    method: "PUT",
                    body: JSON.stringify({ accountId: assigneeId }),
                });
            } else {
                await unassign(issueKey);
            }

            await call(`/rest/api/2/issue/${issueKey}/transitions`, {
                method: "POST",
                body: JSON.stringify({ transition: { id: done.id } }),
            });
            return true;
        },

        unassignIssue: unassign,
    };
}

/**
 * `gh` runs from the checkout that owns the ticket, because it reads the repository from its working
 * directory. The caller maps a ticket to a path; an unknown ticket falls back to whatever it chooses.
 */
export function createGithubTransport(
    pathForTicket: (ticketKey: string, connection?: string) => string | null,
): GhTransport {
    return {
        async findPullRequests(
            ticketKey: string,
            connection?: string,
        ): Promise<GhPullRequest[]> {
            const repositoryPath = pathForTicket(ticketKey, connection);
            // No checkout means no repository to ask about; the ticket's project was never resolved.
            if (repositoryPath === null) return [];
            const listed = await runCommand(
                "gh",
                [
                    "pr",
                    "list",
                    "--search",
                    `${ticketKey} in:title`,
                    "--state",
                    "all",
                    "--json",
                    "number,url,state",
                    "--limit",
                    "20",
                ],
                repositoryPath,
            );
            if (listed.code !== 0) {
                throw new Error(`gh pr list failed: ${listed.stderr.trim()}`);
            }
            const pullRequests: GhPullRequest[] = [];
            for (const summary of parsePullRequests(listed.stdout)) {
                const detail = await runCommand(
                    "gh",
                    ["pr", "view", String(summary.number), "--json", "reviews"],
                    repositoryPath,
                );
                pullRequests.push({
                    number: summary.number,
                    url: summary.url,
                    state:
                        summary.state === "MERGED" || summary.state === "CLOSED"
                            ? summary.state
                            : "OPEN",
                    reviews:
                        detail.code === 0 ? parseReviews(detail.stdout) : [],
                });
            }
            return pullRequests;
        },
    };
}

export async function runAgent(
    request: AgentRunRequest,
    command: string = "opencode",
): Promise<AgentRunResult> {
    const args = ["run", "--format", "json", "--auto"];
    if (request.session) args.push("--session", request.session);
    args.push(request.prompt);

    const result = await runCommand(
        command,
        args,
        request.project.path,
        request.env,
    );
    if (result.code !== 0) {
        return {
            ok: false,
            summary: result.stderr.trim() || `opencode exited ${result.code}`,
        };
    }
    const session =
        extractSessionId(result.stdout) ?? request.session ?? undefined;
    if (!session) {
        return { ok: false, summary: "opencode produced no session id" };
    }
    return { ok: true, session };
}

/**
 * `opencode session list --format json` output.
 *
 * `updated` is epoch milliseconds; an entry without a usable id or timestamp is dropped, because the
 * cleanup pass keeps anything it cannot reason about.
 */
export function parseSessionList(payload: string): SessionSummary[] {
    let parsed: unknown;
    try {
        parsed = JSON.parse(payload);
    } catch {
        return [];
    }
    if (!Array.isArray(parsed)) return [];
    const sessions: SessionSummary[] = [];
    for (const item of parsed) {
        if (item === null || typeof item !== "object") continue;
        const record = item as Record<string, unknown>;
        if (typeof record.id !== "string" || record.id === "") continue;
        if (
            typeof record.updated !== "number" ||
            !Number.isFinite(record.updated)
        )
            continue;
        sessions.push({
            id: record.id,
            updatedAt: new Date(record.updated).toISOString(),
        });
    }
    return sessions;
}

export async function listOpencodeSessions(
    cwd: string,
): Promise<SessionSummary[]> {
    const result = await runCommand(
        "opencode",
        ["session", "list", "--format", "json", "-n", "500"],
        cwd,
    );
    if (result.code !== 0) {
        throw new Error(
            `opencode session list failed: ${result.stderr.trim()}`,
        );
    }
    return parseSessionList(result.stdout);
}

export async function deleteOpencodeSession(
    id: string,
    cwd: string,
): Promise<void> {
    const result = await runCommand("opencode", ["session", "delete", id], cwd);
    if (result.code !== 0) {
        throw new Error(
            `opencode session delete ${id} failed: ${result.stderr.trim()}`,
        );
    }
}

export async function vacuumOpencodeDatabase(cwd: string): Promise<void> {
    const result = await runCommand("opencode", ["db", "VACUUM;"], cwd);
    if (result.code !== 0) {
        throw new Error(`opencode db VACUUM failed: ${result.stderr.trim()}`);
    }
}
