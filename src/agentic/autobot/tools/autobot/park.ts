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
export const PARK_PHASES = [
    "refining",
    "awaiting_restate",
    "awaiting_plan",
] as const;
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
    /**
     * Slack timestamp of the question, e.g. `1767261600.000100`. It is both the reply watermark and
     * the start of the reminder clock, so the record carries one clock rather than two.
     */
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
        record.session === undefined ||
        record.session === null ||
        record.session === ""
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
    // Reminders count from the last reminder, and from the question before the first one.
    const last =
        park.lastReminderAt === undefined
            ? Number.NaN
            : Date.parse(park.lastReminderAt);
    if (!Number.isNaN(last)) return now.getTime() - last >= REMIND_AFTER_MS;
    const asked = slackTsToMs(park.askedAt);
    // An unreadable timestamp cannot order a reminder; prefer waiting over nagging.
    return asked !== null && now.getTime() - asked >= REMIND_AFTER_MS;
}

/** A Slack timestamp in epoch milliseconds, or `null` when it is not one. */
export function slackTsToMs(ts: string): number | null {
    const seconds = Number(ts);
    return Number.isFinite(seconds) ? Math.round(seconds * 1000) : null;
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

/**
 * The on-disk name of a park.
 *
 * Both halves are external input — a Jira key comes from the API, a project name from configuration —
 * so neither is used raw: `/` would create a directory, `..` would leave the parent, and two Jira
 * sites can hand back the same key. Encoding both keeps one park per (project, ticket) and inside the
 * parks directory.
 */
export function threadKey(project: string, ticket: string): string {
    const encode = (value: string): string =>
        value.replace(
            /[^A-Za-z0-9_-]/g,
            (ch) => `%${ch.charCodeAt(0).toString(16)}`,
        );
    return `${encode(project)}--${encode(ticket)}`;
}

export function parkFileName(park: {
    project: string;
    ticket: string;
}): string {
    return `${threadKey(park.project, park.ticket)}.json`;
}
