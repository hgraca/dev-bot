import { describe, expect, test } from "bun:test";

import {
  humanReviews,
  pollGithub,
  selectPullRequest,
  type GhPullRequest,
  type GhReview,
  type GhTransport,
} from "./github.ts";

const review = (id: string, authorLogin: string, submittedAt: string): GhReview => ({
  id,
  authorLogin,
  body: `review ${id}`,
  submittedAt,
});

const pullRequest = (
  number: number,
  state: GhPullRequest["state"],
  reviews: GhReview[] = [],
  url = `https://github.com/GET-E/core/pull/${number}`,
): GhPullRequest => ({ number, url, state, reviews });

describe("selectPullRequest", () => {
  test("is null when the ticket has no pull request", () => {
    expect(selectPullRequest([])).toBeNull();
  });

  test("prefers a merged pull request over an open one", () => {
    const selected = selectPullRequest([pullRequest(9, "OPEN"), pullRequest(8, "MERGED")]);
    expect(selected?.number).toBe(8);
  });

  test("prefers an open pull request over a closed one", () => {
    const selected = selectPullRequest([pullRequest(9, "CLOSED"), pullRequest(8, "OPEN")]);
    expect(selected?.number).toBe(8);
  });

  test("takes the highest number among equals", () => {
    expect(selectPullRequest([pullRequest(8, "OPEN"), pullRequest(9, "OPEN")])?.number).toBe(9);
  });

  test("does not mutate its input", () => {
    const input = [pullRequest(9, "OPEN"), pullRequest(8, "MERGED")];
    selectPullRequest(input);
    expect(input.map((item) => item.number)).toEqual([9, 8]);
  });
});

describe("humanReviews", () => {
  test("is empty without reviews", () => {
    expect(humanReviews([], "autobot")).toEqual([]);
  });

  test("ignores AutoBot's own reviews", () => {
    expect(humanReviews([review("1", "autobot", "2026-11-11T10:00:00Z")], "autobot")).toEqual([]);
  });

  test("returns every human review in submission order", () => {
    const selected = humanReviews(
      [
        review("2", "human", "2026-11-11T10:00:00Z"),
        review("1", "human", "2026-11-10T10:00:00Z"),
        review("3", "autobot", "2026-11-12T10:00:00Z"),
      ],
      "autobot",
    );
    expect(selected.map((entry) => entry.id)).toEqual(["1", "2"]);
  });
});

describe("pollGithub", () => {
  const ticket = { key: "ARC-1", state: null };

  test("returns a null pull request when there is none", async () => {
    const transport: GhTransport = { async findPullRequests() { return []; } };
    expect(await pollGithub({ tickets: [ticket], transport, botLogin: "autobot" })).toEqual([
      { key: "ARC-1", pullRequest: null, pendingReviews: [] },
    ]);
  });

  test("reports the selected pull request and its newest human review", async () => {
    const transport: GhTransport = {
      async findPullRequests() {
        return [
          pullRequest(9, "OPEN", [
            review("1", "human", "2026-11-10T10:00:00Z"),
            review("2", "autobot", "2026-11-11T10:00:00Z"),
          ]),
        ];
      },
    };
    const items = await pollGithub({ tickets: [ticket], transport, botLogin: "autobot" });
    expect(items[0]?.pullRequest?.number).toBe(9);
    expect(items[0]?.pendingReviews[0]?.id).toBe("1");
  });

  test("queries each ticket in order", async () => {
    const asked: string[] = [];
    const transport: GhTransport = {
      async findPullRequests(key) {
        asked.push(key);
        return [];
      },
    };
    await pollGithub({
      tickets: [ticket, { key: "ARC-2", state: null }],
      transport,
      botLogin: "autobot",
    });
    expect(asked).toEqual(["ARC-1", "ARC-2"]);
  });
});
