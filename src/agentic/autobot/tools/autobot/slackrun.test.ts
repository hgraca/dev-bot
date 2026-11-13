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
    askedAt: String(Date.parse("2026-01-01T10:00:00.000Z") / 1000),
    ...over,
});

function harness(options: {
    messages?: SlackMessage[];
    threadReplies?: Record<string, SlackMessage[]>;
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
        replies: async (threadTs: string) =>
            (options.threadReplies ?? {})[threadTs] ?? [],
        answer: async (target: Park, text: string) => {
            state.answered.push({ ticket: target.ticket, text });
            if (options.answerOk === false)
                return { ok: false, reason: "agent failed" };
            state.parks = state.parks.filter(
                (entry) => entry.ticket !== target.ticket,
            );
            return { ok: true };
        },
        post: async (text: string, threadTs: string) => {
            state.posted.push({ text, threadTs });
            return "1767262100.000500";
        },
        savePark: (entry: Park) => {
            state.saved.push(entry);
            state.parks = state.parks.map((existing) =>
                existing.ticket === entry.ticket ? entry : existing,
            );
        },
        clearPark: (entry: Park) => {
            state.cleared.push(entry.ticket);
            state.parks = state.parks.filter(
                (existing) =>
                    !(
                        existing.ticket === entry.ticket &&
                        existing.project === entry.project
                    ),
            );
        },
        log: () => {},
    };
    return { deps, state };
}

describe("runSlackPass", () => {
    test("resumes the run a reply answers, and clears the park", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U123",
                    text: "yes",
                    threadTs: "1700000000.000100",
                },
            ],
        });
        const report = await runSlackPass(deps);
        expect(report.answered).toEqual(["ARC-1"]);
        expect(state.answered[0]?.text).toBe("yes");
        expect(state.cleared).toEqual(["ARC-1"]);
    });

    test("does not remind a ticket answered in the same pass", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U123",
                    text: "yes",
                    threadTs: "1700000000.000100",
                },
            ],
        });
        await runSlackPass(deps);
        expect(state.posted).toEqual([]);
    });

    test("keeps the park when the resume fails", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U123",
                    text: "yes",
                    threadTs: "1700000000.000100",
                },
            ],
            answerOk: false,
        });
        const report = await runSlackPass(deps);
        expect(report.answered).toEqual([]);
        expect(state.cleared).toEqual([]);
    });

    test("ignores a reply from someone else", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U999",
                    text: "yes",
                    threadTs: "1700000000.000100",
                },
            ],
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
            parks: [park({ askedAt: "1767266700.000000" })],
        });
        const report = await runSlackPass(deps);
        expect(report.reminded).toEqual([]);
        expect(state.posted).toEqual([]);
    });

    test("advances the watermark to the newest message seen", async () => {
        const { deps } = harness({
            messages: [
                { ts: "1767261000.000100", userId: "U123", text: "old" },
                { ts: "1767262000.000200", userId: "U123", text: "new" },
            ],
        });
        const report = await runSlackPass(deps);
        expect(report.watermark).toBe("1767262000.000200");
    });

    test("ignores a reply that answers nothing", async () => {
        const { deps, state } = harness({
            messages: [
                { ts: "1767262000.000400", userId: "U123", text: "hello" },
            ],
            parks: [
                park(),
                park({ ticket: "ARC-2", threadTs: "1700000009.000900" }),
            ],
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
        expect(
            answerPrompt(park({ lastReminderAt: undefined }), "ok"),
        ).toContain("ok");
    });
});

function depsNow(): number {
    return (
        new Date("2026-01-01T11:30:00.000Z").getTime() -
        REMIND_AFTER_MS +
        60_000
    );
}

describe("slack pass hardening", () => {
    test("a message older than the question is not its answer", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1000.000100",
                    userId: "U123",
                    text: "from before the question",
                    threadTs: "1700000000.000100",
                },
            ],
        });
        const report = await runSlackPass(deps);
        expect(report.answered).toEqual([]);
        expect(state.answered).toEqual([]);
    });

    test("reads thread replies that history does not return", async () => {
        const { deps, state } = harness({
            messages: [],
            threadReplies: {
                "1700000000.000100": [
                    {
                        ts: "1767262000.000400",
                        userId: "U123",
                        text: "yes",
                        threadTs: "1700000000.000100",
                    },
                ],
            },
        });
        const report = await runSlackPass(deps);
        expect(report.answered).toEqual(["ARC-1"]);
        expect(state.answered[0]?.text).toBe("yes");
    });

    test("holds the watermark at the reply that failed", async () => {
        const { deps } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U123",
                    text: "yes",
                    threadTs: "1700000000.000100",
                },
            ],
            answerOk: false,
        });
        const report = await runSlackPass(deps);
        expect(report.watermark).toBeUndefined();
    });

    test("a second reply to the same ticket does not resume it twice", async () => {
        const { deps, state } = harness({
            messages: [
                {
                    ts: "1767262000.000400",
                    userId: "U123",
                    text: "first",
                    threadTs: "1700000000.000100",
                },
                {
                    ts: "1767262100.000500",
                    userId: "U123",
                    text: "second",
                    threadTs: "1700000000.000100",
                },
            ],
        });
        const report = await runSlackPass(deps);
        expect(report.answered).toEqual(["ARC-1"]);
        expect(state.answered).toHaveLength(1);
    });
});
