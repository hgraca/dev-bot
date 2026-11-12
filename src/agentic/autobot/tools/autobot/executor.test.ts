import { describe, expect, test } from "bun:test";

import { executeAction, MAX_ATTEMPTS, type ExecutorDeps } from "./executor.ts";
import { decideFollowups } from "./followups.ts";
import type { FollowupAction } from "./followups.ts";
import type { GhPullRequest, GhReview } from "./github.ts";
import type { JiraComment, JiraPollItem } from "./jira.ts";
import type { AutobotState } from "./state.ts";

const state = (over: Partial<AutobotState> = {}): AutobotState => ({
  instance: "me",
  project: "core",
  session: "ses_1",
  ...over,
});

const ticket = (over: Partial<JiraPollItem> = {}): JiraPollItem => ({
  key: "ARC-1",
  summary: "",
  status: "",
  assigneeId: "bot",
  reporterId: "reporter-1",
  state: null,
  pendingComments: [],
  ...over,
});

const comment = (id: string): JiraComment => ({ id, authorId: "human", body: `body ${id}`, created: "" });
const review = (id: string): GhReview => ({
  id,
  authorLogin: "human",
  body: `review ${id}`,
  submittedAt: "2026-11-11T10:00:00Z",
});
const pullRequest = (over: Partial<GhPullRequest> = {}): GhPullRequest => ({
  number: 1,
  url: "https://github.com/GET-e/core/pull/1",
  state: "OPEN",
  reviews: [],
  ...over,
});

function fakeDeps(overrides: Partial<ExecutorDeps> = {}) {
  const calls: string[] = [];
  const saved: Array<{ key: string; state: AutobotState }> = [];
  const deps: ExecutorDeps = {
    instance: "me",
    async runAgent(request) {
      calls.push(`run:${request.session ?? "new"}:${request.project.name}`);
      return { ok: true, session: "ses_new" };
    },
    async saveState(key, next) {
      calls.push(`save:${key}:${next.inflight ?? "-"}`);
      saved.push({ key, state: next });
    },
    async clearState(key) {
      calls.push(`clear:${key}`);
    },
    async comment(key) {
      calls.push(`comment:${key}`);
    },
    async closeTicket(key, requestedBy) {
      calls.push(`close:${key}:${requestedBy ?? "-"}`);
      return true;
    },
    async unassignTicket(key) {
      calls.push(`unassign:${key}`);
    },
    async recordSession(id) {
      calls.push(`record:${id}`);
    },
    resolveProject() {
      return { name: "core", path: "/gete/core" };
    },
    ...overrides,
  };
  return { deps, calls, saved };
}

describe("executeAction — skip", () => {
  test("does nothing", async () => {
    const { deps, calls } = fakeDeps();
    const outcome = await executeAction({ kind: "skip", ticket: ticket(), reason: "nothing new" }, deps);
    expect(outcome).toEqual({ kind: "skip", performed: false, reason: "nothing new" });
    expect(calls).toEqual([]);
  });
});

describe("executeAction — start", () => {
  test("starts a session and records it on the ticket", async () => {
    const { deps, calls, saved } = fakeDeps();
    const action: FollowupAction = {
      kind: "start",
      ticket: ticket({ pendingComments: [comment("7")] }),
    };

    const outcome = await executeAction(action, deps);

    expect(outcome.performed).toBe(true);
    expect(calls).toEqual(["run:new:core", "record:ses_new", "save:ARC-1:-"]);
    expect(saved[0]?.state).toEqual({
      instance: "me",
      project: "core",
      session: "ses_new",
      last_comment_id: "7",
      phase: "waiting",
      requested_by: "reporter-1",
    });
  });

  test("asks which repository when none resolves", async () => {
    const { deps, calls } = fakeDeps({ resolveProject: () => null });
    const outcome = await executeAction({ kind: "start", ticket: ticket() }, deps);
    expect(outcome).toMatchObject({ performed: false, reason: "no project" });
    expect(calls).toEqual(["comment:ARC-1", "unassign:ARC-1"]);
  });

  test("does not record a state when the agent fails", async () => {
    const { deps, calls } = fakeDeps({
      runAgent: async () => ({ ok: false, summary: "auth failed" }),
    });
    const outcome = await executeAction({ kind: "start", ticket: ticket() }, deps);
    expect(outcome).toMatchObject({ performed: false, reason: "auth failed" });
    expect(calls).toEqual([]);
  });
});

describe("executeAction — continue", () => {
  test("records inflight before invoking and promotes it after", async () => {
    const { deps, calls, saved } = fakeDeps();
    const action: FollowupAction = {
      kind: "continue",
      ticket: ticket({ state: state(), pendingComments: [comment("11")] }),
      comment: comment("11"),
    };

    const outcome = await executeAction(action, deps);

    expect(outcome.performed).toBe(true);
    expect(calls).toEqual(["save:ARC-1:11", "run:ses_1:core", "save:ARC-1:-"]);
    expect(saved[1]?.state.last_comment_id).toBe("11");
    expect(saved[1]?.state.inflight).toBeNull();
    expect(saved[1]?.state.inflight_attempts).toBeUndefined();
  });

  test("increments the attempt count on a retry", async () => {
    const { deps, saved } = fakeDeps();
    const action: FollowupAction = {
      kind: "continue",
      ticket: ticket({ state: state({ inflight: "11", inflight_attempts: 2 }) }),
      comment: comment("11"),
    };
    await executeAction(action, deps);
    expect(saved[0]?.state.inflight_attempts).toBe(3);
  });

  test("stops at the cap and advances the watermark", async () => {
    const { deps, calls, saved } = fakeDeps();
    const action: FollowupAction = {
      kind: "continue",
      ticket: ticket({ state: state({ inflight: "11", inflight_attempts: MAX_ATTEMPTS }) }),
      comment: comment("11"),
    };

    const outcome = await executeAction(action, deps);

    expect(outcome).toMatchObject({ performed: false, reason: "retry cap reached" });
    expect(calls).toEqual(["comment:ARC-1", "save:ARC-1:-"]);
    expect(saved[0]?.state.last_comment_id).toBe("11");
    expect(saved[0]?.state.phase).toBe("blocked");
  });

  test("refuses to continue a ticket without a session", async () => {
    const { deps, calls } = fakeDeps();
    const outcome = await executeAction(
      { kind: "continue", ticket: ticket(), comment: comment("1") },
      deps,
    );
    expect(outcome).toMatchObject({ performed: false, reason: "no session on the ticket" });
    expect(calls).toEqual([]);
  });

  test("leaves inflight set when the agent fails, so the tick retries", async () => {
    const { deps, saved } = fakeDeps({ runAgent: async () => ({ ok: false }) });
    await executeAction(
      { kind: "continue", ticket: ticket({ state: state() }), comment: comment("11") },
      deps,
    );
    expect(saved).toHaveLength(1);
    expect(saved[0]?.state.inflight).toBe("11");
  });
});

describe("executeAction — review", () => {
  test("the saved watermark stops the same review being picked again", async () => {
    const { deps, saved } = fakeDeps();
    const pr = pullRequest();
    const feedback = review("9");

    await executeAction(
      { kind: "review", ticket: ticket({ state: state() }), pullRequest: pr, review: feedback },
      deps,
    );
    const next = saved[saved.length - 1]!.state;

    const actions = decideFollowups({
      jira: [ticket({ state: next })],
      github: [{ key: "ARC-1", pullRequest: pr, pendingReviews: [feedback] }],
      config: { pollJira: true, pollGithub: true, prompts: [] },
      instance: "me",
    });
    expect(actions[0]?.kind).not.toBe("review");
  });

  test("promotes last_review_at rather than the comment watermark", async () => {
    const { deps, saved } = fakeDeps();
    const action: FollowupAction = {
      kind: "review",
      ticket: ticket({ state: state() }),
      pullRequest: pullRequest(),
      review: review("9"),
    };

    await executeAction(action, deps);

    expect(saved[1]?.state.last_review_at).toBe("2026-11-11T10:00:00Z");
    expect(saved[1]?.state.last_comment_id).toBeUndefined();
  });
});

describe("executeAction — terminal states", () => {
  test("finish closes the ticket with its original owner and clears the state", async () => {
    const { deps, calls } = fakeDeps();
    await executeAction(
      {
        kind: "finish",
        ticket: ticket({ state: state({ requested_by: "reporter-1" }) }),
        pullRequest: pullRequest({ state: "MERGED" }),
      },
      deps,
    );
    expect(calls).toEqual(["close:ARC-1:reporter-1", "clear:ARC-1"]);
  });

  test("finish leaves the state when the workflow has no Done transition", async () => {
    const { deps, calls } = fakeDeps({ closeTicket: async () => false });
    const outcome = await executeAction(
      {
        kind: "finish",
        ticket: ticket({ state: state({ requested_by: "reporter-1" }) }),
        pullRequest: pullRequest({ state: "MERGED" }),
      },
      deps,
    );
    expect(outcome).toMatchObject({ performed: false, reason: "no Done transition" });
    expect(calls).not.toContain("clear:ARC-1");
  });

  test("abandon comments and clears", async () => {
    const { deps, calls } = fakeDeps();
    await executeAction(
      {
        kind: "abandon",
        ticket: ticket({ state: state() }),
        pullRequest: pullRequest({ state: "CLOSED" }),
      },
      deps,
    );
    expect(calls).toEqual(["comment:ARC-1", "unassign:ARC-1", "clear:ARC-1"]);
  });

  test("reconcile names the dead instance and clears", async () => {
    const { deps, calls } = fakeDeps();
    let body = "";
    await executeAction(
      { kind: "reconcile", ticket: ticket({ state: state({ instance: "gone" }) }) },
      { ...deps, comment: async (_key, text) => void (body = text) },
    );
    expect(body).toContain("gone");
    expect(calls).toEqual(["clear:ARC-1"]);
  });
});
