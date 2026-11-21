/**
 * Turning a follow-up decision into side effects.
 *
 * Every dependency is injected, so the ordering that matters is asserted by tests rather than observed
 * by hand: a comment or review records `inflight` *before* invoking the agent and promotes it only on
 * success. A failed start has no session yet, so it simply retries on the next tick.
 *
 * A failed comment or review is retried on the next tick, because `inflight` survives the failure.
 * After `MAX_ATTEMPTS` the watermark is advanced and the ticket is told, so a permanently failing item
 * cannot loop forever and a later comment is still seen.
 */

import type { FollowupAction } from "./followups.ts";
import { PHASE_ABANDONED, PHASE_DONE, type AutobotState } from "./state.ts";
import { TRIGGER_LABEL } from "./jira.ts";

export interface ProjectRef {
    name: string;
    path: string;
}

export interface AgentRunRequest {
    project: ProjectRef;
    /** Existing session to continue, or `null` to start one. */
    session: string | null;
    ticketKey: string;
    prompt: string;
    /** Extra environment for the run, so the agent can address its own ticket from `autobot say`. */
    env?: Record<string, string>;
}

export interface AgentRunResult {
    ok: boolean;
    /** Session id, required when the run started a new session. */
    session?: string;
    summary?: string;
}

export interface ExecutionOutcome {
    kind: string;
    performed: boolean;
    reason?: string;
}

export const MAX_ATTEMPTS = 3;

export interface ExecutorDeps {
    /** This harness's instance id, written into every state it creates. */
    instance: string;
    runAgent(request: AgentRunRequest): Promise<AgentRunResult>;
    saveState(ticketKey: string, state: AutobotState): Promise<void>;
    clearState(ticketKey: string): Promise<void>;
    comment(ticketKey: string, body: string): Promise<void>;
    closeTicket(ticketKey: string, requestedBy?: string): Promise<boolean>;
    addLabels(ticketKey: string, labels: string[]): Promise<void>;
    removeLabel(ticketKey: string, label: string): Promise<void>;
    /** Remember a session this module created, so cleanup never deletes someone else's. */
    recordSession(sessionId: string): Promise<void>;
    /**
     * Give a park written during this run the session that owns it.
     *
     * The first run of a ticket creates the session, so a question it asks cannot name it: the park is
     * written mid-run by the agent, and only here is the id known.
     */
    attachSession?(
        ticketKey: string,
        session: string,
        project: string,
    ): Promise<void>;
    resolveProject(
        ticketKey: string,
        state: AutobotState | null,
    ): ProjectRef | null;
    /**
     * The prompt that starts a run, from the AutoBot command's body with the ticket substituted.
     *
     * Injected because the body is a file in the install: 2.x does not dispatch a slash command
     * from a run message anyway.
     */
    startPrompt(ticketKey: string): string;
}

type Watermark = "last_comment_id" | "last_review_at";

function commentPrompt(ticketKey: string, body: string): string {
    return `A human replied on ${ticketKey}:\n\n${body}\n\nContinue the work.`;
}

function reviewPrompt(pullRequestUrl: string, body: string): string {
    return `Review feedback on ${pullRequestUrl}:\n\n${body}\n\nAddress it.`;
}

async function start(
    action: Extract<FollowupAction, { kind: "start" }>,
    deps: ExecutorDeps,
) {
    const { ticket } = action;
    const project = deps.resolveProject(ticket.key, null);
    if (!project) {
        await deps.comment(
            ticket.key,
            "AutoBot could not tell which repository to work in. Name it in the ticket and assign it again.",
        );
        // Mark it blocked and drop the trigger label, or the next tick repeats the same comment.
        await deps.addLabels(ticket.key, ["auto-bot-blocked"]);
        await deps.removeLabel(ticket.key, TRIGGER_LABEL);
        return { kind: "start", performed: false, reason: "no project" };
    }

    const result = await deps.runAgent({
        project,
        session: null,
        ticketKey: ticket.key,
        prompt: deps.startPrompt(ticket.key),
        env: { DEV_BOT_AUTOBOT_TICKET: ticket.key },
    });
    if (!result.ok || !result.session) {
        return {
            kind: "start",
            performed: false,
            reason: result.summary ?? "agent failed",
        };
    }

    await deps.recordSession(result.session);
    await deps.attachSession?.(ticket.key, result.session, project.name);
    await deps.saveState(ticket.key, {
        instance: deps.instance,
        project: project.name,
        session: result.session,
        last_comment_id: ticket.pendingComments.at(-1)?.id,
        phase: "waiting",
        requested_by: ticket.reporterId ?? undefined,
    });
    return { kind: "start", performed: true };
}

async function resume(
    kind: "continue" | "review",
    ticket: Extract<FollowupAction, { kind: "continue" | "review" }>["ticket"],
    itemId: string,
    watermarkValue: string,
    prompt: string,
    watermark: Watermark,
    deps: ExecutorDeps,
    extra: Partial<AutobotState> = {},
): Promise<ExecutionOutcome> {
    const current = ticket.state;
    if (!current) {
        return { kind, performed: false, reason: "no session on the ticket" };
    }
    const project = deps.resolveProject(ticket.key, current);
    if (!project) {
        return { kind, performed: false, reason: "no project" };
    }

    const attempts =
        (current.inflight === itemId ? (current.inflight_attempts ?? 0) : 0) +
        1;
    if (attempts > MAX_ATTEMPTS) {
        await deps.comment(
            ticket.key,
            `AutoBot could not apply ${itemId} after ${MAX_ATTEMPTS} attempts — it needs a human.`,
        );
        await deps.saveState(ticket.key, {
            ...current,
            [watermark]: watermarkValue,
            ...extra,
            inflight: null,
            inflight_attempts: undefined,
            phase: "blocked",
        });
        return { kind, performed: false, reason: "retry cap reached" };
    }

    await deps.saveState(ticket.key, {
        ...current,
        inflight: itemId,
        inflight_attempts: attempts,
        phase: "working",
    });

    const result = await deps.runAgent({
        project,
        session: current.session,
        ticketKey: ticket.key,
        prompt,
        env: {
            DEV_BOT_AUTOBOT_TICKET: ticket.key,
            DEV_BOT_AUTOBOT_SESSION: current.session,
        },
    });
    if (!result.ok) {
        return {
            kind,
            performed: false,
            reason: result.summary ?? "agent failed",
        };
    }

    await deps.saveState(ticket.key, {
        ...current,
        [watermark]: watermarkValue,
        ...extra,
        inflight: null,
        inflight_attempts: undefined,
        phase: "waiting",
    });
    return { kind, performed: true };
}

export async function executeAction(
    action: FollowupAction,
    deps: ExecutorDeps,
): Promise<ExecutionOutcome> {
    switch (action.kind) {
        case "skip":
            return { kind: "skip", performed: false, reason: action.reason };

        case "start":
            return start(action, deps);

        case "continue":
            return resume(
                "continue",
                action.ticket,
                action.comment.id,
                action.comment.id,
                commentPrompt(action.ticket.key, action.comment.body),
                "last_comment_id",
                deps,
            );

        case "review":
            return resume(
                "review",
                action.ticket,
                action.review.id,
                action.review.submittedAt,
                reviewPrompt(action.pullRequest.url, action.review.body),
                "last_review_at",
                deps,
                { last_review_id: action.review.id },
            );

        case "finish": {
            const closed = await deps.closeTicket(
                action.ticket.key,
                action.ticket.state?.requested_by,
            );
            if (!closed) {
                // The workflow has no Done transition. Keep the state so the ticket stays visible.
                return {
                    kind: "finish",
                    performed: false,
                    reason: "no Done transition",
                };
            }
            // The label and the phase keep the ticket out of the queue without erasing its history.
            await deps.addLabels(action.ticket.key, ["auto-bot-done"]);
            if (action.ticket.state) {
                await deps.saveState(action.ticket.key, {
                    ...action.ticket.state,
                    phase: PHASE_DONE,
                });
            }
            return { kind: "finish", performed: true };
        }

        case "abandon":
            await deps.comment(
                action.ticket.key,
                "The pull request was closed without being merged — AutoBot is stopping here.",
            );
            await deps.addLabels(action.ticket.key, ["auto-bot-abandoned"]);
            if (action.ticket.state) {
                await deps.saveState(action.ticket.key, {
                    ...action.ticket.state,
                    phase: PHASE_ABANDONED,
                });
            }
            return { kind: "abandon", performed: true };

        case "reconcile":
            await deps.comment(
                action.ticket.key,
                `The AutoBot session for this ticket lived on ${action.ticket.state?.instance ?? "another host"}, which is no longer running. Clearing it so the work can be picked up again.`,
            );
            await deps.clearState(action.ticket.key);
            return { kind: "reconcile", performed: true };
    }
}
