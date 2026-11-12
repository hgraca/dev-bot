import { describe, expect, test } from "bun:test";

import type { AutobotConfig } from "./config.ts";
import { decideFollowups, type FollowupAction, type FollowupInput } from "./followups.ts";
import type { GhPullRequest, GhReview, GithubPollItem } from "./github.ts";
import type { JiraComment, JiraPollItem } from "./jira.ts";
import type { AutobotState } from "./state.ts";

const config = (over: Partial<AutobotConfig> = {}): AutobotConfig => ({
  pollJira: true,
  pollGithub: true,
  prompts: [],
  ...over,
});

const state = (over: Partial<AutobotState> = {}): AutobotState => ({
  instance: "me",
  project: "dev-bot",
  session: "ses_1",
  ...over,
});

const ticket = (
  key: string,
  session: AutobotState | null,
  comments: JiraComment | JiraComment[] | null = null,
): JiraPollItem => ({
  key,
  summary: "",
  status: "",
  assigneeId: "bot",
  reporterId: "reporter",
  state: session,
  pendingComments: comments === null ? [] : Array.isArray(comments) ? comments : [comments],
});

const comment = (id: string): JiraComment => ({
  id,
  authorId: "human",
  body: `comment ${id}`,
  created: "2026-11-11T10:00:00Z",
});

const review = (id: string, submittedAt: string): GhReview => ({
  id,
  authorLogin: "human",
  body: `review ${id}`,
  submittedAt,
});

const pullRequest = (over: Partial<GhPullRequest> = {}): GhPullRequest => ({
  number: 1,
  url: "https://github.com/GET-e/core/pull/1",
  state: "OPEN",
  reviews: [],
  ...over,
});

const gh = (
  key: string,
  pr: GhPullRequest | null,
  reviews: GhReview | GhReview[] | null = null,
): GithubPollItem => ({
  key,
  pullRequest: pr,
  pendingReviews: reviews === null ? [] : Array.isArray(reviews) ? reviews : [reviews],
});

const decide = (input: Partial<FollowupInput>) =>
  decideFollowups({
    jira: [],
    github: [],
    config: config(),
    instance: "me",
    ...input,
  });

describe("decideFollowups — new work", () => {
  test("returns nothing when there is nothing", () => {
    expect(decide({})).toEqual([]);
  });

  test("starts a session for an assigned ticket with no state", () => {
    expect(decide({ jira: [ticket("ARC-1", null)] }).map((action) => action.kind)).toEqual(["start"]);
  });

  test("does not start when Jira polling is off", () => {
    const actions = decide({ jira: [ticket("ARC-1", null)], config: config({ pollJira: false }) });
    expect(actions.map((action) => action.kind)).toEqual(["skip"]);
  });
});

describe("decideFollowups — comments", () => {
  test("continues when a human comment is newer than the watermark", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ last_comment_id: "10" }), comment("11"))],
    });
    expect(actions[0]?.kind).toBe("continue");
  });

  test("skips a comment already handled", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ last_comment_id: "11" }), comment("11"))],
    });
    expect(actions[0]?.kind).toBe("skip");
  });

  test("continues on the first comment when no watermark exists", () => {
    const actions = decide({ jira: [ticket("ARC-1", state(), comment("1"))] });
    expect(actions[0]?.kind).toBe("continue");
  });

  test("answers a burst one at a time, oldest first", () => {
    const actions = decide({
      jira: [
        ticket("ARC-1", state({ last_comment_id: "10" }), [comment("11"), comment("12")]),
      ],
    });
    expect(actions[0]?.kind).toBe("continue");
    expect((actions[0] as { comment: JiraComment }).comment.id).toBe("11");
  });

  test("retries a failed item before a newer one", () => {
    const actions = decide({
      jira: [
        ticket(
          "ARC-1",
          state({ last_comment_id: "10", inflight: "11", inflight_attempts: 1 }),
          [comment("11"), comment("12")],
        ),
      ],
    });
    expect((actions[0] as { comment: JiraComment }).comment.id).toBe("11");
  });

  test("skips when the only comments are AutoBot's", () => {
    expect(decide({ jira: [ticket("ARC-1", state())] })[0]?.kind).toBe("skip");
  });
});

describe("decideFollowups — pull requests", () => {
  test("finishes on a merged pull request", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state())],
      github: [gh("ARC-1", pullRequest({ state: "MERGED" }))],
    });
    expect(actions[0]?.kind).toBe("finish");
  });

  test("starts a session instead of closing a ticket it never owned", () => {
    const actions = decide({
      jira: [ticket("ARC-1", null)],
      github: [gh("ARC-1", pullRequest({ state: "MERGED" }))],
    });
    expect(actions[0]?.kind).toBe("start");
  });

  test("abandons on a closed pull request", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state())],
      github: [gh("ARC-1", pullRequest({ state: "CLOSED" }))],
    });
    expect(actions[0]?.kind).toBe("abandon");
  });

  test("prefers a merged pull request over an unanswered comment", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state(), comment("5"))],
      github: [gh("ARC-1", pullRequest({ state: "MERGED" }))],
    });
    expect(actions).toHaveLength(1);
    expect(actions[0]?.kind).toBe("finish");
  });

  test("ignores the pull request when GitHub polling is off", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state())],
      github: [gh("ARC-1", pullRequest({ state: "MERGED" }))],
      config: config({ pollGithub: false }),
    });
    expect(actions[0]?.kind).toBe("skip");
  });
});

describe("decideFollowups — reviews", () => {
  test("reviews when feedback is newer than the watermark", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ last_review_at: "2026-11-10T10:00:00Z" }))],
      github: [
        gh("ARC-1", pullRequest(), review("1", "2026-11-11T10:00:00Z")),
      ],
    });
    expect(actions[0]?.kind).toBe("review");
  });

  test("skips review feedback already handled", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ last_review_at: "2026-11-12T10:00:00Z" }))],
      github: [gh("ARC-1", pullRequest(), review("1", "2026-11-11T10:00:00Z"))],
    });
    expect(actions[0]?.kind).toBe("skip");
  });

  test("advances through reviews submitted in the same second", () => {
    const same = "2026-11-11T10:00:00Z";
    const burst = [review("1", same), review("2", same)];

    const first = decide({
      jira: [ticket("ARC-1", state({ last_review_at: same, last_review_id: "1" }))],
      github: [gh("ARC-1", pullRequest(), burst)],
    });
    expect((first[0] as { review: GhReview }).review.id).toBe("2");

    const exhausted = decide({
      jira: [ticket("ARC-1", state({ last_review_at: same, last_review_id: "2" }))],
      github: [gh("ARC-1", pullRequest(), burst)],
    });
    expect(exhausted[0]?.kind).toBe("skip");
  });

  test("reviews on the first feedback when no watermark exists", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state())],
      github: [gh("ARC-1", pullRequest(), review("1", "2026-11-11T10:00:00Z"))],
    });
    expect(actions[0]?.kind).toBe("review");
  });
});

describe("decideFollowups — ownership", () => {
  test("leaves a ticket owned by another live instance alone", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ instance: "other" }), comment("1"))],
      liveInstances: ["me", "other"],
    });
    expect(actions[0]?.kind).toBe("skip");
    const action = actions[0] as Extract<FollowupAction, { kind: "skip" }>;
    expect(action.reason).toContain("live instance other");
  });

  test("reconciles a ticket whose owning instance is gone", () => {
    const actions = decide({ jira: [ticket("ARC-1", state({ instance: "gone" }))] });
    expect(actions[0]?.kind).toBe("reconcile");
  });

  test("does not reconcile when Jira polling is off", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ instance: "gone" }))],
      config: config({ pollJira: false }),
    });
    expect(actions[0]?.kind).toBe("skip");
  });

  test("treats an instance listed as live as live", () => {
    const actions = decide({
      jira: [ticket("ARC-1", state({ instance: "peer" }))],
      liveInstances: ["me", "peer"],
    });
    expect(actions[0]?.kind).toBe("skip");
  });
});
