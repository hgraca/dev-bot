/**
 * The `Autobot session` field payload.
 *
 * Jira holds one single-line text field with a 255-character limit, so the payload is written with
 * short keys and read back into a readable shape. A malformed payload throws rather than parsing to
 * `null`: treating it as absent would make the next tick start a second session for a ticket that
 * already has one.
 */

export const STATE_FIELD_ID = "customfield_10877";
/** The field's limit; the compact encoding leaves several dozen characters of headroom. */
export const MAX_STATE_LENGTH = 255;

const FORMAT_VERSION = 1;

export interface AutobotState {
  /** Harness instance that owns the session, e.g. `autobot@host`. */
  instance: string;
  /** Managed project name the session runs in. */
  project: string;
  /** opencode session id. */
  session: string;
  last_comment_id?: string;
  last_review_at?: string;
  /** Id of the last handled review, so two submitted in the same second stay ordered. */
  last_review_id?: string;
  /** Comment or review being handled right now; promoted on success. */
  inflight?: string | null;
  /** Attempts already spent on `inflight`, so a failing item cannot loop forever. */
  inflight_attempts?: number;
  phase?: string;
  /** Assignee before AutoBot took the ticket, restored on completion. */
  requested_by?: string;
}

/** Wire key per field. Versioned by `v` so the encoding can change without breaking readers. */
const WIRE = {
  instance: "i",
  project: "p",
  session: "s",
  last_comment_id: "c",
  last_review_at: "r",
  last_review_id: "ri",
  inflight: "f",
  inflight_attempts: "a",
  phase: "ph",
  requested_by: "by",
} as const;

type WireKey = (typeof WIRE)[keyof typeof WIRE];

function pick(record: Record<string, unknown>, key: WireKey): unknown {
  if (key in record) return record[key];
  const long = (Object.keys(WIRE) as Array<keyof typeof WIRE>).find((name) => WIRE[name] === key);
  return long === undefined ? undefined : record[long];
}

function requireString(value: unknown, key: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`autobot state: "${key}" must be a non-empty string`);
  }
  return value;
}

function optionalString(value: unknown, key: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new Error(`autobot state: "${key}" must be a string`);
  }
  return value;
}

function optionalCount(value: unknown, key: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw new Error(`autobot state: "${key}" must be a non-negative integer`);
  }
  return value as number;
}

/** Parse the field value. `null`/empty means the ticket has no session yet. */
export function parseState(raw: unknown): AutobotState | null {
  if (raw === null || raw === undefined || raw === "") return null;
  if (typeof raw !== "string") {
    throw new Error(`autobot state: expected a string, got ${typeof raw}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("autobot state: not valid JSON");
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("autobot state: not a JSON object");
  }
  const record = parsed as Record<string, unknown>;
  const inflightRaw = pick(record, WIRE.inflight);
  const inflight =
    inflightRaw === undefined || inflightRaw === null
      ? inflightRaw
      : requireString(inflightRaw, "inflight");
  return {
    instance: requireString(pick(record, WIRE.instance), "instance"),
    project: requireString(pick(record, WIRE.project), "project"),
    session: requireString(pick(record, WIRE.session), "session"),
    last_comment_id: optionalString(pick(record, WIRE.last_comment_id), "last_comment_id"),
    last_review_at: optionalString(pick(record, WIRE.last_review_at), "last_review_at"),
    last_review_id: optionalString(pick(record, WIRE.last_review_id), "last_review_id"),
    inflight,
    inflight_attempts: optionalCount(pick(record, WIRE.inflight_attempts), "inflight_attempts"),
    phase: optionalString(pick(record, WIRE.phase), "phase"),
    requested_by: optionalString(pick(record, WIRE.requested_by), "requested_by"),
  };
}

function compact(state: AutobotState): Record<string, unknown> {
  const wire: Record<string, unknown> = {
    v: FORMAT_VERSION,
    [WIRE.instance]: state.instance,
    [WIRE.project]: state.project,
    [WIRE.session]: state.session,
  };
  if (state.last_comment_id !== undefined) wire[WIRE.last_comment_id] = state.last_comment_id;
  if (state.last_review_at !== undefined) wire[WIRE.last_review_at] = state.last_review_at;
  if (state.last_review_id !== undefined) wire[WIRE.last_review_id] = state.last_review_id;
  if (state.inflight !== undefined) wire[WIRE.inflight] = state.inflight;
  if (state.inflight_attempts !== undefined) wire[WIRE.inflight_attempts] = state.inflight_attempts;
  if (state.phase !== undefined) wire[WIRE.phase] = state.phase;
  if (state.requested_by !== undefined) wire[WIRE.requested_by] = state.requested_by;
  return wire;
}

/** Serialise for writing back to the field, refusing a payload the field cannot hold. */
export function serialiseState(state: AutobotState): string {
  const text = JSON.stringify(compact(state));
  if (text.length > MAX_STATE_LENGTH) {
    throw new Error(
      `autobot state: ${text.length} characters exceeds the ${MAX_STATE_LENGTH}-character field limit`,
    );
  }
  return text;
}
