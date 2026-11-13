/**
 * A parked run: what AutoBot asked, in which thread, and when it last reminded the user.
 *
 * The record lives on disk rather than in the Jira state field for two reasons: the field is capped at
 * 255 characters and already carries the session, and a park is transient — it disappears the moment
 * the question is answered, which is not something a ticket's history should record.
 *
 * Parking is the mechanism that makes an unattended run possible. A run cannot wait for an answer, so
 * it asks, records the question here and ends; the next tick starts a fresh run on the reply.
 */

/** The phases in which a run has asked something and stopped. */
export const PARK_PHASES = ["refining", "awaiting_restate", "awaiting_plan"] as const;
export type ParkPhase = (typeof PARK_PHASES)[number];

/** How long a park waits before reminding, and between reminders. */
export const REMIND_AFTER_MS = 60 * 60 * 1000;

export interface Park {
  ticket: string;
  /** Managed project the run belongs to, so the resume runs in the right checkout. */
  project: string;
  /** Slack connection (the resolved user id), so two connections cannot answer each other's parks. */
  connection: string;
  channel: string;
  /** Thread the question was posted in; a reply inside it addresses this park. */
  threadTs: string;
  phase: ParkPhase;
  question: string;
  /** Slack timestamp of the question, used as the reply watermark. */
  askedAt: string;
  /** ISO timestamp of the last reminder, so the hourly cadence survives restarts. */
  lastReminderAt?: string;
  /**
   * opencode session to resume. The first run of a ticket creates it, so a park it writes is filled
   * in afterwards by the executor.
   */
  session?: string;
}

function oneOfPhase(value: unknown): ParkPhase {
  const phase = typeof value === "string" ? value : "";
  if (!(PARK_PHASES as readonly string[]).includes(phase)) {
    throw new Error(
      `autobot park: "phase" must be one of ${PARK_PHASES.join(", ")}, got "${String(value)}"`,
    );
  }
  return phase as ParkPhase;
}

function text(value: unknown, key: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`autobot park: "${key}" must be a non-empty string`);
  }
  return value;
}

export function parsePark(raw: unknown): Park {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("autobot park: not a JSON object");
  }
  const record = raw as Record<string, unknown>;
  const lastReminderAt =
    record.lastReminderAt === undefined || record.lastReminderAt === null
      ? undefined
      : text(record.lastReminderAt, "lastReminderAt");
  const session =
    record.session === undefined || record.session === null || record.session === ""
      ? undefined
      : text(record.session, "session");
  return {
    ticket: text(record.ticket, "ticket"),
    project: text(record.project, "project"),
    connection: text(record.connection, "connection"),
    channel: text(record.channel, "channel"),
    threadTs: text(record.threadTs, "threadTs"),
    phase: oneOfPhase(record.phase),
    question: text(record.question, "question"),
    askedAt: text(record.askedAt, "askedAt"),
    ...(lastReminderAt === undefined ? {} : { lastReminderAt }),
    ...(session === undefined ? {} : { session }),
  };
}

export function serialisePark(park: Park): string {
  return JSON.stringify(parsePark(park));
}

/**
 * Whether the user is overdue a reminder.
 *
 * The clock starts at the question, then at the last reminder, so the cadence is hourly and endless:
 * a park is answered or it is not, and nothing expires underneath it.
 */
export function isReminderDue(park: Park, now: Date): boolean {
  const since = park.lastReminderAt === undefined ? Number.NaN : Date.parse(park.lastReminderAt);
  if (Number.isNaN(since)) {
    const asked = Date.parse(park.askedAt);
    // An unparseable `askedAt` cannot order a reminder; prefer waiting over nagging.
    return !Number.isNaN(asked) && now.getTime() - asked >= REMIND_AFTER_MS;
  }
  const last = new Date(since);
  return now.getTime() - last.getTime() >= REMIND_AFTER_MS;
}

/** The reminder text: the question again, so the user does not have to scroll back. */
export function reminderText(park: Park): string {
  return `Still waiting on your answer for ${park.ticket}:\n\n${park.question}`;
}

/**
 * The park a message answers.
 *
 * A reply inside a thread belongs to that thread's park. A message typed into the direct message
 * itself carries no `thread_ts`, so it addresses the only parked ticket in that channel — and is
 * ignored when several are parked, because guessing which ticket a bare "yes" belongs to is how the
 * wrong pull request gets built.
 */
export function matchPark(
  parks: Park[],
  channel: string,
  threadTs: string | undefined,
): Park | null {
  const inChannel = parks.filter((park) => park.channel === channel);
  if (threadTs !== undefined) {
    return inChannel.find((park) => park.threadTs === threadTs) ?? null;
  }
  return inChannel.length === 1 ? (inChannel[0] ?? null) : null;
}
