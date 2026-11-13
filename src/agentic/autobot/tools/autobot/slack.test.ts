import { describe, expect, test } from "bun:test";

import {
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
