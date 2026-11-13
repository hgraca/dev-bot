import { describe, expect, test } from "bun:test";

import type { Park } from "./park.ts";
import { REMIND_AFTER_MS } from "./park.ts";
import type { SlackMessage } from "./slack.ts";
import { answerPrompt, runSlackPass } from "./slackrun.ts";

const park = (over: Partial<Park> = {}): Park => ({
  ticket: "ARC-1",
  project: "dev-bot",
  connection: "U123",
  channel: "D456",
  threadTs: "1700000000.000100",
  phase: "awaiting_plan",
  question: "Shall I start with the skill?",
  askedAt: new Date("2026-01-01T10:00:00.000Z").toISOString(),
  ...over,
});

function harness(options: {
  messages?: SlackMessage[];
  parks?: Park[];
  answerOk?: boolean;
}) {
  const state = {
    parks: options.parks ?? [park()],
    saved: [] as Park[],
    cleared: [] as string[],
    posted: [] as Array<{ text: string; threadTs: string }>,
    answered: [] as Array<{ ticket: string; text: string }>,
  };
  const deps = {
    now: new Date("2026-01-01T11:30:00.000Z"),
    channel: "D456",
    connection: "U123",
    watermark: undefined as string | undefined,
    parks: () => state.parks,
    history: async () => options.messages ?? [],
    answer: async (target: Park, text: string) => {
      state.answered.push({ ticket: target.ticket, text });
      if (options.answerOk === false) return { ok: false, reason: "agent failed" };
      state.parks = state.parks.filter((entry) => entry.ticket !== target.ticket);
      return { ok: true };
    },
    post: async (text: string, threadTs: string) => {
      state.posted.push({ text, threadTs });
      return "1700000500.000500";
    },
    savePark: (entry: Park) => {
      state.saved.push(entry);
      state.parks = state.parks.map((existing) =>
        existing.ticket === entry.ticket ? entry : existing,
      );
    },
    clearPark: (ticket: string) => {
      state.cleared.push(ticket);
      state.parks = state.parks.filter((entry) => entry.ticket !== ticket);
    },
    log: () => {},
  };
  return { deps, state };
}

describe("runSlackPass", () => {
  test("resumes the run a reply answers, and clears the park", async () => {
    const { deps, state } = harness({
      messages: [{ ts: "1700000400.000400", userId: "U123", text: "yes", threadTs: "1700000000.000100" }],
    });
    const report = await runSlackPass(deps);
    expect(report.answered).toEqual(["ARC-1"]);
    expect(state.answered[0]?.text).toBe("yes");
    expect(state.cleared).toEqual(["ARC-1"]);
  });

  test("does not remind a ticket answered in the same pass", async () => {
    const { deps, state } = harness({
      messages: [{ ts: "1700000400.000400", userId: "U123", text: "yes", threadTs: "1700000000.000100" }],
    });
    await runSlackPass(deps);
    expect(state.posted).toEqual([]);
  });

  test("keeps the park when the resume fails", async () => {
    const { deps, state } = harness({
      messages: [{ ts: "1700000400.000400", userId: "U123", text: "yes", threadTs: "1700000000.000100" }],
      answerOk: false,
    });
    const report = await runSlackPass(deps);
    expect(report.answered).toEqual([]);
    expect(state.cleared).toEqual([]);
  });

  test("ignores a reply from someone else", async () => {
    const { deps, state } = harness({
      messages: [{ ts: "1700000400.000400", userId: "U999", text: "yes", threadTs: "1700000000.000100" }],
    });
    const report = await runSlackPass(deps);
    expect(report.answered).toEqual([]);
    expect(state.answered).toEqual([]);
  });

  test("reminds an unanswered park in its thread", async () => {
    const { deps, state } = harness({});
    const report = await runSlackPass(deps);
    expect(report.reminded).toEqual(["ARC-1"]);
    expect(state.posted[0]?.threadTs).toBe("1700000000.000100");
    expect(state.saved[0]?.lastReminderAt).toBe(deps.now.toISOString());
  });

  test("stays quiet while the reminder is not yet due", async () => {
    const { deps, state } = harness({
      parks: [park({ askedAt: new Date(depsNow()).toISOString() })],
    });
    const report = await runSlackPass(deps);
    expect(report.reminded).toEqual([]);
    expect(state.posted).toEqual([]);
  });

  test("advances the watermark to the newest message seen", async () => {
    const { deps } = harness({
      messages: [
        { ts: "1700000100.000100", userId: "U123", text: "old" },
        { ts: "1700000200.000200", userId: "U123", text: "new" },
      ],
    });
    const report = await runSlackPass(deps);
    expect(report.watermark).toBe("1700000200.000200");
  });

  test("ignores a reply that answers nothing", async () => {
    const { deps, state } = harness({
      messages: [{ ts: "1700000400.000400", userId: "U123", text: "hello" }],
      parks: [park(), park({ ticket: "ARC-2", threadTs: "1700000009.000900" })],
    });
    const report = await runSlackPass(deps);
    expect(report.answered).toEqual([]);
    expect(state.answered).toEqual([]);
  });
});

describe("answerPrompt", () => {
  test("carries the question the answer belongs to", () => {
    const prompt = answerPrompt(park(), "yes, proceed");
    expect(prompt).toContain("Shall I start with the skill?");
    expect(prompt).toContain("yes, proceed");
    expect(prompt).toContain("ARC-1");
  });

  test("is stable for a reminder-free park", () => {
    expect(answerPrompt(park({ lastReminderAt: undefined }), "ok")).toContain("ok");
  });
});

function depsNow(): number {
  return new Date("2026-01-01T11:30:00.000Z").getTime() - REMIND_AFTER_MS + 60_000;
}
