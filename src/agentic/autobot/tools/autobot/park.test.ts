import { describe, expect, test } from "bun:test";

import {
    isReminderDue,
    parkFileName,
    matchPark,
    parsePark,
    REMIND_AFTER_MS,
    reminderText,
    serialisePark,
    type Park,
} from "./park.ts";

const at = (iso: string): string => String(Date.parse(iso) / 1000);

const park = (over: Partial<Park> = {}): Park => ({
    ticket: "ARC-1",
    project: "dev-bot",
    connection: "U123",
    channel: "D456",
    threadTs: "1700000000.000100",
    phase: "awaiting_plan",
    question: "Shall I start with the skill?",
    askedAt: at("2026-01-01T10:00:00.000Z"),
    ...over,
});

describe("park record", () => {
    test("round-trips through its wire form", () => {
        expect(parsePark(JSON.parse(serialisePark(park())))).toEqual(park());
    });

    test("rejects a phase it does not know", () => {
        expect(() => parsePark({ ...park(), phase: "sleeping" })).toThrow(
            '"phase" must be one of',
        );
    });

    test("rejects a missing question", () => {
        expect(() => parsePark({ ...park(), question: "" })).toThrow(
            '"question" must be a non-empty',
        );
    });
});

describe("reminders", () => {
    const asked = new Date("2026-01-01T10:00:00.000Z");

    test("waits an hour before the first reminder", () => {
        const before = new Date(asked.getTime() + REMIND_AFTER_MS - 1000);
        expect(
            isReminderDue(park({ askedAt: at(asked.toISOString()) }), before),
        ).toBe(false);
    });

    test("reminds an hour after the question", () => {
        const due = new Date(asked.getTime() + REMIND_AFTER_MS);
        expect(
            isReminderDue(park({ askedAt: at(asked.toISOString()) }), due),
        ).toBe(true);
    });

    test("counts from the last reminder once one was sent", () => {
        const reminded = new Date(asked.getTime() + 2 * REMIND_AFTER_MS);
        const next = new Date(reminded.getTime() + REMIND_AFTER_MS - 1000);
        expect(
            isReminderDue(
                park({
                    askedAt: at(asked.toISOString()),
                    lastReminderAt: reminded.toISOString(),
                }),
                next,
            ),
        ).toBe(false);
    });

    test("repeats the question so the user need not scroll", () => {
        expect(reminderText(park())).toContain("ARC-1");
        expect(reminderText(park())).toContain("Shall I start with the skill?");
    });
});

describe("matchPark", () => {
    test("a threaded reply belongs to that thread", () => {
        const parks = [
            park(),
            park({ ticket: "ARC-2", threadTs: "1700000009.000900" }),
        ];
        expect(matchPark(parks, "D456", "1700000009.000900")?.ticket).toBe(
            "ARC-2",
        );
    });

    test("a bare reply addresses the only parked ticket", () => {
        expect(matchPark([park()], "D456", undefined)?.ticket).toBe("ARC-1");
    });

    test("a bare reply is ignored while several are parked", () => {
        expect(
            matchPark([park(), park({ ticket: "ARC-2" })], "D456", undefined),
        ).toBeNull();
    });

    test("another channel never matches", () => {
        expect(matchPark([park()], "D999", "1700000000.000100")).toBeNull();
    });

    test("an unknown thread does not fall through to the channel", () => {
        expect(matchPark([park()], "D456", "1700000099.009900")).toBeNull();
    });
});

describe("parkFileName", () => {
    test("keeps the project and ticket apart", () => {
        expect(parkFileName({ project: "dev-bot", ticket: "ARC-1" })).toBe(
            "dev-bot--ARC-1.json",
        );
    });

    test("cannot leave the parks directory", () => {
        const name = parkFileName({
            project: "../../etc",
            ticket: "../../passwd",
        });
        expect(name).not.toContain("/");
        expect(name.endsWith(".json")).toBe(true);
    });

    test("separates two sites that share a key", () => {
        expect(parkFileName({ project: "a", ticket: "ARC-1" })).not.toBe(
            parkFileName({ project: "b", ticket: "ARC-1" }),
        );
    });
});
