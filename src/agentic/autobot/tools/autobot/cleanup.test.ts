import { describe, expect, test } from "bun:test";

import {
    cleanupSessions,
    selectOrphans,
    type SessionSummary,
} from "./cleanup.ts";

const NOW = new Date("2026-11-11T12:00:00Z");

const session = (id: string, updatedAt: string): SessionSummary => ({
    id,
    updatedAt,
});

describe("selectOrphans", () => {
    test("keeps a referenced session however old it is", () => {
        const sessions = [session("ses_old", "2020-01-01T00:00:00Z")];
        expect(selectOrphans(sessions, new Set(["ses_old"]), NOW)).toEqual([]);
    });

    test("keeps an unreferenced session inside the grace window", () => {
        const sessions = [session("ses_new", "2026-11-11T11:30:00Z")];
        expect(selectOrphans(sessions, new Set(), NOW)).toEqual([]);
    });

    test("deletes an unreferenced session past the grace window", () => {
        const sessions = [session("ses_old", "2026-11-09T12:00:00Z")];
        expect(selectOrphans(sessions, new Set(), NOW)).toEqual(["ses_old"]);
    });

    test("honours a custom grace window", () => {
        const sessions = [session("ses_recent", "2026-11-11T09:00:00Z")];
        expect(selectOrphans(sessions, new Set(), NOW, 1)).toEqual([
            "ses_recent",
        ]);
        expect(selectOrphans(sessions, new Set(), NOW, 12)).toEqual([]);
    });

    test("keeps a session whose timestamp cannot be read", () => {
        const sessions = [session("ses_broken", "not a date")];
        expect(selectOrphans(sessions, new Set(), NOW)).toEqual([]);
    });

    test("returns every orphan and no survivors", () => {
        const sessions = [
            session("ses_a", "2020-01-01T00:00:00Z"),
            session("ses_b", "2026-11-11T11:59:00Z"),
            session("ses_c", "2020-01-01T00:00:00Z"),
        ];
        expect(selectOrphans(sessions, new Set(["ses_b"]), NOW)).toEqual([
            "ses_a",
            "ses_c",
        ]);
    });
});

describe("cleanupSessions", () => {
    test("reports nothing for an empty session list", async () => {
        const report = await cleanupSessions({
            sessions: [],
            referenced: new Set(),
            now: NOW,
            deleteSession: async () => {},
        });
        expect(report).toEqual({ deleted: [], kept: 0 });
    });

    test("deletes each orphan in order and vacuums once", async () => {
        const calls: string[] = [];
        const report = await cleanupSessions({
            sessions: [
                session("ses_a", "2020-01-01T00:00:00Z"),
                session("ses_live", "2020-01-01T00:00:00Z"),
                session("ses_b", "2020-01-01T00:00:00Z"),
            ],
            referenced: new Set(["ses_live"]),
            now: NOW,
            deleteSession: async (id) => {
                calls.push(`delete:${id}`);
            },
            vacuum: async () => {
                calls.push("vacuum");
            },
        });
        expect(calls).toEqual(["delete:ses_a", "delete:ses_b", "vacuum"]);
        expect(report).toEqual({ deleted: ["ses_a", "ses_b"], kept: 1 });
    });

    test("does not vacuum when nothing was deleted", async () => {
        const calls: string[] = [];
        await cleanupSessions({
            sessions: [session("ses_live", "2020-01-01T00:00:00Z")],
            referenced: new Set(["ses_live"]),
            now: NOW,
            deleteSession: async (id) => {
                calls.push(`delete:${id}`);
            },
            vacuum: async () => {
                calls.push("vacuum");
            },
        });
        expect(calls).toEqual([]);
    });

    test("skips the vacuum when no vacuum dependency is supplied", async () => {
        const report = await cleanupSessions({
            sessions: [session("ses_a", "2020-01-01T00:00:00Z")],
            referenced: new Set(),
            now: NOW,
            deleteSession: async () => {},
        });
        expect(report.deleted).toEqual(["ses_a"]);
    });
});
