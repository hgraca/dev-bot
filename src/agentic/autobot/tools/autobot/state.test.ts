import { describe, expect, test } from "bun:test";

import { MAX_STATE_LENGTH, parseState, serialiseState } from "./state.ts";

const minimal = { instance: "autobot@host", project: "dev-bot", session: "ses_abc" };

describe("parseState", () => {
  test("treats null, undefined and empty as no session", () => {
    expect(parseState(null)).toBeNull();
    expect(parseState(undefined)).toBeNull();
    expect(parseState("")).toBeNull();
  });

  test("parses a minimal payload", () => {
    expect(parseState(JSON.stringify(minimal))).toEqual({
      ...minimal,
      last_comment_id: undefined,
      last_review_at: undefined,
      inflight: undefined,
      phase: undefined,
      requested_by: undefined,
    });
  });

  test("parses the full payload", () => {
    const full = {
      ...minimal,
      last_comment_id: "10042",
      last_review_at: "2026-11-11T18:00:00Z",
      inflight: "10043",
      phase: "working",
      requested_by: "712020:7bb09315",
    };
    expect(parseState(JSON.stringify(full))).toEqual(full);
  });

  test("allows an explicitly cleared inflight", () => {
    expect(parseState(JSON.stringify({ ...minimal, inflight: null }))?.inflight).toBeNull();
  });

  test("parses an attempt count", () => {
    expect(parseState(JSON.stringify({ ...minimal, inflight: "1", inflight_attempts: 2 }))?.inflight_attempts).toBe(2);
  });

  test("rejects a negative or fractional attempt count", () => {
    expect(() => parseState(JSON.stringify({ ...minimal, inflight_attempts: -1 }))).toThrow(
      /"inflight_attempts" must be a non-negative integer/,
    );
    expect(() => parseState(JSON.stringify({ ...minimal, inflight_attempts: 1.5 }))).toThrow(
      /"inflight_attempts" must be a non-negative integer/,
    );
  });

  test("rejects a non-string field value", () => {
    expect(() => parseState({})).toThrow(/expected a string/);
  });

  test("rejects malformed JSON", () => {
    expect(() => parseState("{not json")).toThrow(/not valid JSON/);
  });

  test("rejects a JSON array", () => {
    expect(() => parseState("[]")).toThrow(/not a JSON object/);
  });

  test("rejects a missing required key and names it", () => {
    expect(() => parseState(JSON.stringify({ instance: "a", project: "b" }))).toThrow(
      /"session" must be a non-empty string/,
    );
  });

  test("rejects a blank required key", () => {
    expect(() => parseState(JSON.stringify({ ...minimal, instance: "  " }))).toThrow(
      /"instance" must be a non-empty string/,
    );
  });

  test("rejects a non-string optional key", () => {
    expect(() => parseState(JSON.stringify({ ...minimal, phase: 7 }))).toThrow(
      /"phase" must be a string/,
    );
  });
});

describe("serialiseState", () => {
  test("round-trips through parseState", () => {
    const state = { ...minimal, last_comment_id: "1", phase: "working" };
    expect(parseState(serialiseState(state))).toEqual({
      ...state,
      last_review_at: undefined,
      inflight: undefined,
      requested_by: undefined,
    });
  });

  test("refuses a payload longer than the field can hold", () => {
    expect(() =>
      serialiseState({ ...minimal, requested_by: "x".repeat(MAX_STATE_LENGTH) }),
    ).toThrow(/exceeds the 255/);
  });

  test("a realistic full payload fits the field", () => {
    const text = serialiseState({
      instance: "autobot@workstation",
      project: "dev-bot",
      session: "ses_f01be292cffex6arnbdgbSdZzq",
      last_comment_id: "10042",
      last_review_at: "2026-11-11T18:00:00Z",
      inflight: "10043",
      inflight_attempts: 2,
      phase: "working",
      requested_by: "712020:7bb09315-b382-4391-a036-5bf5de3052ed",
    });
    expect(text.length).toBeLessThanOrEqual(MAX_STATE_LENGTH);
    expect(parseState(text)?.session).toBe("ses_f01be292cffex6arnbdgbSdZzq");
  });
});
