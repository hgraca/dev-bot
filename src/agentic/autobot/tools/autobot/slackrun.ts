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
  /** Every park on this connection, across projects. */
  parks(): Park[];
  history(oldest?: string): Promise<SlackMessage[]>;
  /** Resume the run that asked `park.question` with the user's answer. */
  answer(
    park: Park,
    text: string,
  ): Promise<{ ok: boolean; reason?: string; session?: string | undefined }>;
  /** Post a reminder in the park's thread. */
  post(text: string, threadTs: string): Promise<string>;
  savePark(park: Park): void;
  clearPark(ticket: string): void;
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
 * Run the pass.
 *
 * A failed resume keeps the park: the reply is not marked handled, so the next tick tries again and
 * the user's answer is not lost. A reminder that fails to post does not advance the reminder clock,
 * for the same reason.
 */
export async function runSlackPass(deps: SlackPassDeps): Promise<SlackPassReport> {
  const report: SlackPassReport = { answered: [], reminded: [], watermark: deps.watermark };
  const messages = await deps.history(deps.watermark);
  const replies = repliesFrom(messages, deps.connection, deps.watermark);
  const parks = deps.parks();

  for (const reply of replies) {
    const park = matchPark(parks, deps.channel, reply.threadTs);
    if (park === null) {
      deps.log(`slack: no parked ticket for the reply at ${reply.ts} — ignored`);
      continue;
    }
    const result = await deps.answer(park, reply.text);
    if (!result.ok) {
      // Keep the park and the watermark: retrying the same reply is cheaper than losing it.
      deps.log(`slack: could not resume ${park.ticket}: ${result.reason ?? "agent failed"}`);
      continue;
    }
    deps.clearPark(park.ticket);
    report.answered.push(park.ticket);
  }

  // Reminders read the parks after the answers, so a ticket answered this pass is already gone.
  const remaining = deps.parks().filter((park) => park.channel === deps.channel);
  for (const park of remaining) {
    if (!isReminderDue(park, deps.now)) continue;
    try {
      await deps.post(reminderText(park), park.threadTs);
    } catch (error) {
      deps.log(`slack: could not remind ${park.ticket}: ${(error as Error).message}`);
      continue;
    }
    deps.savePark({ ...park, lastReminderAt: deps.now.toISOString() });
    report.reminded.push(park.ticket);
  }

  const last = messages.at(-1);
  if (last !== undefined && (report.watermark === undefined || Number(last.ts) > Number(report.watermark))) {
    report.watermark = last.ts;
  }
  return report;
}
