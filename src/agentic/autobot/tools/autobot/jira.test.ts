import { describe, expect, test } from "bun:test";

import {
  buildJql,
  humanComments,
  pollJira,
  toTicket,
  type JiraComment,
  type JiraTransport,
  type RawJiraIssue,
} from "./jira.ts";
import { STATE_FIELD_ID } from "./state.ts";

const state = { instance: "autobot@host", project: "dev-bot", session: "ses_abc" };

describe("buildJql", () => {
  test("builds the new-work query", () => {
    expect(buildJql("bot-1", STATE_FIELD_ID, "new")).toBe(
      'assignee = "bot-1" AND cf[10877] IS EMPTY ORDER BY updated ASC',
    );
  });

  test("builds the continuation query", () => {
    expect(buildJql("bot-1", STATE_FIELD_ID, "continuation")).toBe(
      'assignee = "bot-1" AND cf[10877] IS NOT EMPTY ORDER BY updated ASC',
    );
  });

  test("accepts a different field id", () => {
    expect(buildJql("bot-1", "customfield_10001")).toContain("cf[10001]");
  });

  test("rejects an empty account id", () => {
    expect(() => buildJql("  ")).toThrow(/account id is required/);
  });

  test("rejects a field id with no digits", () => {
    expect(() => buildJql("bot-1", "autobot")).toThrow(/carries no field id/);
  });
});

describe("toTicket", () => {
  test("normalises a full issue", () => {
    const raw: RawJiraIssue = {
      key: "ARC-1",
      fields: {
        summary: "Do the thing",
        status: { name: "In Progress" },
        assignee: { accountId: "bot-1" },
        reporter: { accountId: "reporter-1" },
        [STATE_FIELD_ID]: JSON.stringify(state),
      },
    };
    expect(toTicket(raw)).toEqual({
      key: "ARC-1",
      summary: "Do the thing",
      status: "In Progress",
      assigneeId: "bot-1",
      reporterId: "reporter-1",
      state: {
        ...state,
        last_comment_id: undefined,
        last_review_at: undefined,
        inflight: undefined,
        phase: undefined,
        pr_url: undefined,
        requested_by: undefined,
      },
    });
  });

  test("defaults the optional fields", () => {
    expect(toTicket({ key: "ARC-2" })).toEqual({
      key: "ARC-2",
      summary: "",
      status: "",
      assigneeId: null,
      reporterId: null,
      state: null,
    });
  });

  test("rejects an issue without a key", () => {
    expect(() => toTicket({ key: "  " })).toThrow(/without a key/);
  });

  test("propagates a malformed state payload", () => {
    expect(() => toTicket({ key: "ARC-3", fields: { [STATE_FIELD_ID]: "{nope" } })).toThrow(
      /not valid JSON/,
    );
  });
});

describe("humanComments", () => {
  const comment = (id: string, authorId: string): JiraComment => ({
    id,
    authorId,
    body: `body ${id}`,
    created: "2026-11-11T18:00:00Z",
  });

  test("is empty when there are no comments", () => {
    expect(humanComments([], "bot")).toEqual([]);
  });

  test("ignores AutoBot's own comments", () => {
    expect(humanComments([comment("1", "bot")], "bot")).toEqual([]);
  });

  test("returns every human comment, oldest first", () => {
    const result = humanComments(
      [comment("100", "human"), comment("9", "human"), comment("10", "human")],
      "bot",
    );
    expect(result.map((entry) => entry.id)).toEqual(["9", "10", "100"]);
  });

  test("ignores AutoBot even when its comment is newest", () => {
    const result = humanComments([comment("5", "human"), comment("99", "bot")], "bot");
    expect(result.map((entry) => entry.id)).toEqual(["5"]);
  });

  test("falls back to string ordering for non-numeric ids", () => {
    const result = humanComments([comment("b", "human"), comment("a", "human")], "bot");
    expect(result.map((entry) => entry.id)).toEqual(["a", "b"]);
  });
});

describe("pollJira", () => {
  const newIssue: RawJiraIssue = { key: "ARC-10", fields: { summary: "new" } };
  const continuedIssue: RawJiraIssue = {
    key: "ARC-11",
    fields: { summary: "ongoing", [STATE_FIELD_ID]: JSON.stringify(state) },
  };

  test("returns new work and continuations, fetching comments for both", async () => {
    const calls: string[] = [];
    const transport: JiraTransport = {
      async search(jql) {
        calls.push(jql);
        return jql.includes("IS NOT EMPTY") ? [continuedIssue] : [newIssue];
      },
      async comments(key) {
        calls.push(`comments:${key}`);
        return [
          { id: "1", authorId: "bot-1", body: "mine", created: "" },
          { id: "2", authorId: "human", body: "question", created: "" },
        ];
      },
    };

    const items = await pollJira({ accountId: "bot-1", transport });

    expect(items.map((item) => item.key)).toEqual(["ARC-10", "ARC-11"]);
    expect(items[0]?.pendingComments[0]?.body).toBe("question");
    expect(items[1]?.pendingComments[0]?.body).toBe("question");
    expect(calls).toEqual([
      buildJql("bot-1", STATE_FIELD_ID, "new"),
      "comments:ARC-10",
      buildJql("bot-1", STATE_FIELD_ID, "continuation"),
      "comments:ARC-11",
    ]);
  });

  test("returns nothing when the searches are empty", async () => {
    const transport: JiraTransport = {
      async search() {
        return [];
      },
      async comments() {
        return [];
      },
    };
    expect(await pollJira({ accountId: "bot-1", transport })).toEqual([]);
  });
});
