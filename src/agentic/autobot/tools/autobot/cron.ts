/**
 * Five-field cron matching.
 *
 * Fields are minute, hour, day-of-month, month, day-of-week, each supporting `*`, `n`, `a-b`,
 * `/step` and comma lists. Day-of-week accepts 0–7 with both 0 and 7 meaning Sunday.
 *
 * When *both* day-of-month and day-of-week are restricted, a date matches if either does — the
 * standard cron rule, which is why `0 0 1 * 1` fires on the 1st of the month and on every Monday.
 *
 * Matching reads the supplied `Date` in the process's local timezone; the tick passes a single
 * `Date` per run so every project is evaluated against the same instant.
 */

interface FieldSpec {
    name: string;
    min: number;
    max: number;
    /** Number of distinct values, which differs from max-min+1 for day-of-week (0 and 7 alias). */
    distinct: number;
}

const FIELDS: FieldSpec[] = [
    { name: "minute", min: 0, max: 59, distinct: 60 },
    { name: "hour", min: 0, max: 23, distinct: 24 },
    { name: "day-of-month", min: 1, max: 31, distinct: 31 },
    { name: "month", min: 1, max: 12, distinct: 12 },
    { name: "day-of-week", min: 0, max: 7, distinct: 7 },
];

export interface CronSchedule {
    minutes: Set<number>;
    hours: Set<number>;
    daysOfMonth: Set<number>;
    months: Set<number>;
    daysOfWeek: Set<number>;
    dayOfMonthRestricted: boolean;
    dayOfWeekRestricted: boolean;
}

const cache = new Map<string, CronSchedule>();

function expandField(raw: string, spec: FieldSpec, where: string): Set<number> {
    const values = new Set<number>();
    for (const part of raw.split(",")) {
        if (part === "") {
            throw new Error(
                `${where}: "schedule" has an empty ${spec.name} field`,
            );
        }
        const chunks = part.split("/");
        if (chunks.length > 2) {
            throw new Error(
                `${where}: "schedule" field "${part}" contains unsupported characters`,
            );
        }
        const [rangeText, stepText] = chunks;
        if (stepText !== undefined && !/^\d+$/.test(stepText)) {
            throw new Error(
                `${where}: "schedule" field "${part}" has an invalid step`,
            );
        }
        const step = stepText === undefined ? 1 : Number(stepText);
        if (step < 1) {
            throw new Error(
                `${where}: "schedule" field "${part}" has an invalid step`,
            );
        }

        let start: number;
        let end: number;
        if (rangeText === "*") {
            start = spec.min;
            end = spec.max;
        } else if (/^\d+$/.test(rangeText)) {
            start = Number(rangeText);
            end = stepText === undefined ? start : spec.max;
        } else if (/^\d+-\d+$/.test(rangeText)) {
            const [from, to] = rangeText.split("-").map(Number);
            start = from;
            end = to;
        } else {
            throw new Error(
                `${where}: "schedule" field "${part}" contains unsupported characters`,
            );
        }

        if (start < spec.min || end > spec.max || start > end) {
            throw new Error(
                `${where}: "schedule" ${spec.name} field "${part}" is out of range`,
            );
        }
        for (let value = start; value <= end; value += step) {
            const normalised =
                spec.name === "day-of-week" && value === 7 ? 0 : value;
            values.add(normalised);
        }
    }
    return values;
}

function isUnrestricted(values: Set<number>, spec: FieldSpec): boolean {
    return values.size >= spec.distinct;
}

/** Parse a five-field cron expression, throwing a `where`-prefixed error when it is malformed. */
export function parseSchedule(
    expression: string,
    where = "schedule",
): CronSchedule {
    const cached = cache.get(expression);
    if (cached) return cached;

    if (typeof expression !== "string" || expression.trim() === "") {
        throw new Error(`${where}: "schedule" must be a non-empty string`);
    }
    const parts = expression.trim().split(/\s+/);
    if (parts.length !== FIELDS.length) {
        throw new Error(
            `${where}: "schedule" must have ${FIELDS.length} fields, got ${parts.length} ("${expression.trim()}")`,
        );
    }

    const [minute, hour, dayOfMonth, month, dayOfWeek] = parts.map(
        (part, index) => expandField(part, FIELDS[index], where),
    );

    const schedule: CronSchedule = {
        minutes: minute,
        hours: hour,
        daysOfMonth: dayOfMonth,
        months: month,
        daysOfWeek: dayOfWeek,
        dayOfMonthRestricted: !isUnrestricted(dayOfMonth, FIELDS[2]),
        dayOfWeekRestricted: !isUnrestricted(dayOfWeek, FIELDS[4]),
    };
    cache.set(expression, schedule);
    return schedule;
}

/** True when `date` falls on the minute described by `schedule`. */
export function matchesSchedule(schedule: CronSchedule, date: Date): boolean {
    if (!schedule.minutes.has(date.getMinutes())) return false;
    if (!schedule.hours.has(date.getHours())) return false;
    if (!schedule.months.has(date.getMonth() + 1)) return false;

    const dayOfMonthMatches = schedule.daysOfMonth.has(date.getDate());
    const dayOfWeekMatches = schedule.daysOfWeek.has(date.getDay());

    if (schedule.dayOfMonthRestricted && schedule.dayOfWeekRestricted) {
        return dayOfMonthMatches || dayOfWeekMatches;
    }
    if (schedule.dayOfMonthRestricted) return dayOfMonthMatches;
    if (schedule.dayOfWeekRestricted) return dayOfWeekMatches;
    return true;
}

/** The entries whose schedule matches `date`, in their original order. */
export function dueEntries<T extends { schedule: string }>(
    entries: T[],
    date: Date,
): T[] {
    return entries.filter((entry) =>
        matchesSchedule(parseSchedule(entry.schedule), date),
    );
}
