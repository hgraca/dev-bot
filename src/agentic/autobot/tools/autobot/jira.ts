/**
 * Reading AutoBot work out of Jira.
 *
 * The transport is injected so the polling logic — the JQL it builds and the way it picks the comment
 * that needs an answer — is testable without a network call. Comments are fetched for both passes,
 * because a new session must record the newest pre-existing comment as its watermark.
 */

import { isSigned } from "./signature.ts";
import { parseState, STATE_FIELD_ID, type AutobotState } from "./state.ts";

/** The label that puts a ticket in AutoBot's queue. */
export const TRIGGER_LABEL = "auto-bot";
/** Labels that take a ticket back out of the queue, one per terminal outcome. */
export const TERMINAL_LABELS = [
    "auto-bot-done",
    "auto-bot-abandoned",
    "auto-bot-blocked",
];

export interface JiraComment {
    id: string;
    authorId: string;
    body: string;
    created: string;
}

export interface JiraTicket {
    key: string;
    summary: string;
    status: string;
    assigneeId: string | null;
    /** The person the ticket is restored to when AutoBot finishes with it. */
    reporterId: string | null;
    state: AutobotState | null;
}

export interface JiraPollItem extends JiraTicket {
    /** Human comments, oldest first. Every one must be answered, not only the newest. */
    pendingComments: JiraComment[];
    /** Which configured connection found this ticket; two sites can share an issue key. */
    connection?: string;
}

export interface RawJiraIssue {
    key: string;
    fields?: {
        summary?: string;
        status?: { name?: string };
        assignee: { accountId?: string } | null;
        reporter?: { accountId?: string } | null;
        [field: string]: unknown;
    };
}

export interface JiraTransport {
    search(jql: string): Promise<RawJiraIssue[]>;
    comments(key: string): Promise<JiraComment[]>;
}

export type JqlMode = "new" | "continuation";

/** `customfield_10877` → `cf[10877]`, which is the form JQL accepts for a custom field. */
function jqlField(stateFieldId: string): string {
    const id = stateFieldId.replace(/[^0-9]/g, "");
    if (id === "")
        throw new Error(`autobot jira: "${stateFieldId}" carries no field id`);
    return `cf[${id}]`;
}

export function buildJql(
    stateFieldId: string = STATE_FIELD_ID,
    mode: JqlMode = "new",
    assignees?: string[],
): string {
    const clause = mode === "new" ? "IS EMPTY" : "IS NOT EMPTY";
    const terminal = TERMINAL_LABELS.map((label) => `"${label}"`).join(", ");
    // An empty list is the caller's signal to poll nothing at all; there is no JQL that says "nobody".
    const assigneeClause =
        assignees === undefined
            ? ""
            : ` AND assignee in (${assignees.map((name) => `"${name.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`).join(", ")})`;
    return (
        `labels = "${TRIGGER_LABEL}" AND labels not in (${terminal})` +
        `${assigneeClause} AND ${jqlField(stateFieldId)} ${clause} ORDER BY updated ASC`
    );
}

export function toTicket(
    raw: RawJiraIssue,
    stateFieldId: string = STATE_FIELD_ID,
): JiraTicket {
    if (typeof raw.key !== "string" || raw.key.trim() === "") {
        throw new Error("autobot jira: an issue without a key");
    }
    const fields = raw.fields ?? {};
    return {
        key: raw.key,
        summary: typeof fields.summary === "string" ? fields.summary : "",
        status: fields.status?.name ?? "",
        assigneeId: fields.assignee?.accountId ?? null,
        reporterId: fields.reporter?.accountId ?? null,
        state: parseState(fields[stateFieldId]),
    };
}

function compareIds(a: string, b: string): number {
    const left = Number(a);
    const right = Number(b);
    if (Number.isFinite(left) && Number.isFinite(right)) return left - right;
    return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * Comments AutoBot has not written, oldest first, so a burst is answered one per tick.
 *
 * Author cannot be the test — there is no separate bot identity — so the signature is.
 */
export function pendingComments(comments: JiraComment[]): JiraComment[] {
    return comments
        .filter((comment) => !isSigned(comment.body))
        .sort((a, b) => compareIds(a.id, b.id));
}

/** One poll pass: new work plus the assigned tickets that carry a session. */
export async function pollJira(options: {
    transport: JiraTransport;
    stateFieldId?: string;
    /** Restrict the query to these assignees; an empty list polls nothing. */
    assignees?: string[];
    /** Called for each ticket that cannot be read, so one bad field does not stop the poll. */
    onError?: (message: string) => void;
}): Promise<JiraPollItem[]> {
    const { transport, stateFieldId = STATE_FIELD_ID, assignees } = options;
    const items: JiraPollItem[] = [];
    if (assignees !== undefined && assignees.length === 0) return items;

    // Comments are read for both passes: a new session must not answer a comment that predates it, so
    // the caller records the newest one as its watermark when the session starts.
    for (const raw of await transport.search(
        buildJql(stateFieldId, "new", assignees),
    )) {
        try {
            const ticket = toTicket(raw, stateFieldId);
            const comments = await transport.comments(ticket.key);
            items.push({
                ...ticket,
                pendingComments: pendingComments(comments),
            });
        } catch (error) {
            options.onError?.(
                `jira: skipping ${raw.key}: ${(error as Error).message}`,
            );
        }
    }

    for (const raw of await transport.search(
        buildJql(stateFieldId, "continuation", assignees),
    )) {
        try {
            const ticket = toTicket(raw, stateFieldId);
            const comments = await transport.comments(ticket.key);
            items.push({
                ...ticket,
                pendingComments: pendingComments(comments),
            });
        } catch (error) {
            options.onError?.(
                `jira: skipping ${raw.key}: ${(error as Error).message}`,
            );
        }
    }

    return items;
}
