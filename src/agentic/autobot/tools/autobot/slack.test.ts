import { afterEach, beforeEach, describe, expect, test } from "bun:test";

import {
    createSlackClient,
    readChannelId,
    readMessages,
    readTs,
    readUserId,
    repliesFrom,
    type SlackMessage,
} from "./slack.ts";

describe("slack responses", () => {
    test("reads the user id", () => {
        expect(readUserId({ ok: true, user: { id: "U123" } })).toBe("U123");
    });

    test("reads the channel id", () => {
        expect(readChannelId({ ok: true, channel: { id: "D456" } })).toBe(
            "D456",
        );
    });

    test("reads the posted timestamp", () => {
        expect(readTs({ ok: true, ts: "1700000000.000100" })).toBe(
            "1700000000.000100",
        );
    });

    test("surfaces slack's error instead of an empty result", () => {
        expect(() =>
            readUserId({ ok: false, error: "users_not_found" }),
        ).toThrow("slack users.lookupByEmail failed: users_not_found");
    });

    test("refuses a response with no id", () => {
        expect(() => readUserId({ ok: true, user: {} })).toThrow("no user id");
    });

    test("reads history oldest first and drops unusable entries", () => {
        const messages = readMessages({
            ok: true,
            messages: [
                { ts: "1700000002.000200", user: "U1", text: "second" },
                {
                    ts: "1700000001.000100",
                    user: "U1",
                    text: "first",
                    thread_ts: "1700000000.000050",
                },
                { text: "no timestamp" },
                { ts: "1700000003.000300", text: "no author" },
            ],
        });
        expect(messages.map((message) => message.text)).toEqual([
            "first",
            "second",
        ]);
        expect(messages[0]?.threadTs).toBe("1700000000.000050");
    });
});

describe("repliesFrom", () => {
    const message = (ts: string, userId: string): SlackMessage => ({
        ts,
        userId,
        text: "x",
    });

    test("keeps only the configured person", () => {
        const replies = repliesFrom(
            [message("2.0", "U1"), message("3.0", "U2")],
            "U1",
            undefined,
        );
        expect(replies.map((reply) => reply.ts)).toEqual(["2.0"]);
    });

    test("ignores anything at or before the watermark", () => {
        const replies = repliesFrom(
            [message("2.0", "U1"), message("3.0", "U1"), message("4.0", "U1")],
            "U1",
            "3.0",
        );
        expect(replies.map((reply) => reply.ts)).toEqual(["4.0"]);
    });

    test("treats an unreadable watermark as no watermark", () => {
        expect(
            repliesFrom([message("2.0", "U1")], "U1", "not-a-ts"),
        ).toHaveLength(1);
    });
});

describe("paging", () => {
    const realFetch = globalThis.fetch;
    const calls: string[] = [];
    let pages: unknown[] = [];

    beforeEach(() => {
        calls.length = 0;
        globalThis.fetch = (async (_url: string, init?: RequestInit) => {
            calls.push(
                String(
                    (
                        JSON.parse(String(init?.body ?? "{}")) as {
                            cursor?: string;
                        }
                    ).cursor ?? "",
                ),
            );
            return {
                ok: true,
                status: 200,
                json: async () => pages.shift(),
            } as unknown as Response;
        }) as unknown as typeof fetch;
    });

    afterEach(() => {
        globalThis.fetch = realFetch;
    });

    test("follows the cursor through every history page", async () => {
        pages = [
            {
                ok: true,
                messages: [{ ts: "2.0", user: "U1", text: "b" }],
                response_metadata: { next_cursor: "c1" },
            },
            {
                ok: true,
                messages: [{ ts: "1.0", user: "U1", text: "a" }],
                response_metadata: { next_cursor: "" },
            },
        ];
        const messages = await createSlackClient("x").history("D1");
        expect(messages.map((message) => message.text)).toEqual(["a", "b"]);
        expect(calls).toEqual(["", "c1"]);
    });

    test("follows the cursor through every thread page", async () => {
        pages = [
            {
                ok: true,
                messages: [{ ts: "1.0", user: "U1", text: "question" }],
                response_metadata: { next_cursor: "c1" },
            },
            {
                ok: true,
                messages: [{ ts: "2.0", user: "U1", text: "answer" }],
                response_metadata: { next_cursor: "" },
            },
        ];
        const replies = await createSlackClient("x").replies("D1", "1.0");
        expect(replies.map((message) => message.text)).toEqual(["answer"]);
        expect(calls).toEqual(["", "c1"]);
    });
});
