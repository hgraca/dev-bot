/**
 * One Slack pass: answer whatever the user replied to, then remind what is still waiting.
 *
 * Ordering matters. A reply is a human blocked on progress, so it is handled before anything is
 * posted; and a park that was just answered must not be reminded in the same pass.
 *
 * Everything here is injected. The decisions — which reply answers which park, when a reminder is
 * due, what the next watermark is — are asserted by tests rather than observed from a live workspace.
 */

import { isReminderDue, matchPark, reminderText, type Park } from "./park.ts";
import { repliesFrom, type SlackMessage } from "./slack.ts";

export interface SlackPassDeps {
    now: Date;
    /** The direct message this pass reads. */
    channel: string;
    /** The one user whose replies count. */
    connection: string;
    /** Messages older than this were already handled; absent means read as much as Slack returns. */
    watermark: string | undefined;
    /** Every park on this connection, across projects. Read fresh once per pass. */
    parks(): Park[];
    history(oldest?: string): Promise<SlackMessage[]>;
    /** Replies inside a message's thread; `conversations.history` does not return them. */
    replies(threadTs: string): Promise<SlackMessage[]>;
    /** Resume the run that asked `park.question` with the user's answer. */
    answer(park: Park, text: string): Promise<{ ok: boolean; reason?: string }>;
    /** Post a reminder in the park's thread. */
    post(text: string, threadTs: string): Promise<string>;
    savePark(park: Park): void;
    /**
     * Remove the park this reply answered.
     *
     * It takes the park, not its ticket: the resumed run may have asked a follow-up question and
     * overwritten the file, and deleting that would strand the question.
     */
    clearPark(park: Park): void;
    log(message: string): void;
}

export interface SlackPassReport {
    answered: string[];
    reminded: string[];
    watermark: string | undefined;
}

/** The prompt a resumed run receives: the question, then the answer, so the reply has a subject. */
export function answerPrompt(park: Park, text: string): string {
    return `You asked on ${park.ticket}:

${park.question}

The user answered:

${text}

Continue the work from where you stopped.`;
}

/**
 * The messages to consider: every top-level message, plus the replies inside each open thread.
 *
 * Threads are read explicitly rather than discovered, because the only threads that matter are the
 * ones a park points at — and reading them means a reply to a question is seen even when the
 * direct message itself has been quiet.
 */
async function readConversation(
    deps: SlackPassDeps,
    parks: Park[],
): Promise<SlackMessage[]> {
    const messages = await deps.history(deps.watermark);
    const seen = new Set(messages.map((message) => `${message.ts}`));
    for (const threadTs of new Set(parks.map((park) => park.threadTs))) {
        for (const reply of await deps.replies(threadTs)) {
            if (seen.has(reply.ts)) continue;
            seen.add(reply.ts);
            messages.push(reply);
        }
    }
    return messages.sort((a, b) => (a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : 0));
}

/**
 * Run the pass.
 *
 * A failed resume keeps the park and holds the watermark at that reply: the next tick retries it, and
 * the user's answer is not scrolled past.
 */
export async function runSlackPass(
    deps: SlackPassDeps,
): Promise<SlackPassReport> {
    const report: SlackPassReport = {
        answered: [],
        reminded: [],
        watermark: deps.watermark,
    };
    const known = deps.parks();
    const messages = await readConversation(deps, known);
    const replies = repliesFrom(messages, deps.connection, deps.watermark);

    // Mutated as answers are handled, so a second reply to the same ticket in one pass cannot resume the
    // same question again.
    const parked = [...known];
    let firstFailure: string | undefined;

    for (const reply of replies) {
        const park = matchPark(parked, deps.channel, reply.threadTs);
        if (park === null) {
            deps.log(
                `slack: no parked ticket for the reply at ${reply.ts} — ignored`,
            );
            continue;
        }
        // A message sent before the question cannot be its answer, whatever the watermark says.
        if (Number(reply.ts) <= Number(park.askedAt)) continue;

        const result = await deps.answer(park, reply.text);
        if (!result.ok) {
            deps.log(
                `slack: could not resume ${park.ticket}: ${result.reason ?? "agent failed"}`,
            );
            firstFailure ??= reply.ts;
            continue;
        }
        deps.clearPark(park);
        const index = parked.findIndex(
            (entry) =>
                entry.ticket === park.ticket && entry.project === park.project,
        );
        if (index !== -1) parked.splice(index, 1);
        report.answered.push(park.ticket);
    }

    // Reminders read the parks after the answers, so a ticket answered this pass is already gone.
    for (const park of deps
        .parks()
        .filter((entry) => entry.channel === deps.channel)) {
        if (!isReminderDue(park, deps.now)) continue;
        try {
            await deps.post(reminderText(park), park.threadTs);
        } catch (error) {
            deps.log(
                `slack: could not remind ${park.ticket}: ${(error as Error).message}`,
            );
            continue;
        }
        deps.savePark({ ...park, lastReminderAt: deps.now.toISOString() });
        report.reminded.push(park.ticket);
    }

    // Stop the watermark at the first unhandled reply: advancing past it would drop the user's answer.
    const ceiling =
        firstFailure === undefined
            ? messages.at(-1)?.ts
            : messages
                  .filter(
                      (message) => Number(message.ts) < Number(firstFailure),
                  )
                  .at(-1)?.ts;
    if (
        ceiling !== undefined &&
        (report.watermark === undefined ||
            Number(ceiling) > Number(report.watermark))
    ) {
        report.watermark = ceiling;
    }
    return report;
}
