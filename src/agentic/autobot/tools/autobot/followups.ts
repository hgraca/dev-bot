/**
 * The follow-up decision: given what Jira and GitHub currently say, what — if anything — should run?
 *
 * Pure by design. No I/O, no model calls: an empty result ends the tick without spending a token, and
 * every rule is exercised by fixtures rather than by a live ticket.
 *
 * At most one action per ticket, chosen by urgency: a merged pull request beats a closed one, which
 * beats review feedback, which beats a ticket comment, which beats starting work. Anything left over
 * is seen by the next tick, so nothing is lost and nothing is invoked twice for the same change.
 */

import type { AutobotConfig } from "./config.ts";
import type { GhPullRequest, GhReview, GithubPollItem } from "./github.ts";
import type { JiraComment, JiraPollItem } from "./jira.ts";
import { isTerminalPhase } from "./state.ts";

export type FollowupAction =
  | { kind: "finish"; ticket: JiraPollItem; pullRequest: GhPullRequest }
  | { kind: "abandon"; ticket: JiraPollItem; pullRequest: GhPullRequest }
  | { kind: "review"; ticket: JiraPollItem; pullRequest: GhPullRequest; review: GhReview }
  | { kind: "continue"; ticket: JiraPollItem; comment: JiraComment }
  | { kind: "start"; ticket: JiraPollItem }
  | { kind: "reconcile"; ticket: JiraPollItem }
  | { kind: "skip"; ticket: JiraPollItem; reason: string };

export interface FollowupInput {
  jira: JiraPollItem[];
  github: GithubPollItem[];
  config: AutobotConfig;
  /** This harness's instance id, as written into the state field. */
  instance: string;
  /** Instances whose sessions are still reachable; defaults to this one. */
  liveInstances?: string[];
}

function isNewerTimestamp(candidate: string, previous?: string): boolean {
  if (previous === undefined || previous === "") return true;
  return candidate > previous;
}

/**
 * The next review after the watermark, by position in the list rather than by id or timestamp.
 *
 * Ids are opaque and timestamps collide, so comparing either one cannot order a burst of reviews
 * submitted in the same second. The list is stable, so advancing past the last handled review's
 * position is monotonic: A then B then nothing, never A, B, A.
 */
function nextReview(
  reviews: Array<{ submittedAt: string; id: string }>,
  previousAt?: string,
  previousId?: string,
): { submittedAt: string; id: string } | null {
  if (previousAt === undefined || previousAt === "") return reviews[0] ?? null;
  const handled = previousId ? reviews.findIndex((review) => review.id === previousId) : -1;
  if (handled >= 0) return reviews[handled + 1] ?? null;
  // The handled review is no longer in the list (deleted or superseded); fall back to the timestamp.
  return reviews.find((review) => review.submittedAt > previousAt) ?? null;
}

function isNewerCommentId(candidate: string, previous?: string): boolean {
  if (previous === undefined || previous === "") return true;
  const left = Number(candidate);
  const right = Number(previous);
  if (Number.isFinite(left) && Number.isFinite(right)) return left > right;
  return candidate > previous;
}

export function decideFollowups(input: FollowupInput): FollowupAction[] {
  const { jira, github, config, instance } = input;
  const live = new Set(input.liveInstances ?? [instance]);
  // Two Jira sites can return the same issue key, so the identity is the pair.
  const ticketId = (item: { key: string; connection?: string }) =>
    `${item.connection ?? ""}\u0000${item.key}`;
  const githubByKey = new Map(github.map((item) => [ticketId(item), item]));
  const actions: FollowupAction[] = [];

  for (const ticket of jira) {
    const state = ticket.state;

    // Finished and abandoned tickets keep their label; the phase is what takes them out of the queue.
    if (isTerminalPhase(state?.phase)) {
      actions.push({ kind: "skip", ticket, reason: `terminal phase ${state?.phase}` });
      continue;
    }

    // A session belongs to one instance. Another live instance means hands off; a dead one means the
    // session is unreachable, so the ticket is handed back rather than silently stuck forever.
    if (state && state.instance !== instance) {
      actions.push(
        live.has(state.instance)
          ? { kind: "skip", ticket, reason: `owned by live instance ${state.instance}` }
          : config.pollJira
            ? { kind: "reconcile", ticket }
            : { kind: "skip", ticket, reason: `owned by dead instance ${state.instance}` },
      );
      continue;
    }

    const githubItem = githubByKey.get(ticketId(ticket));
    const pullRequest = githubItem?.pullRequest ?? null;

    // Terminal states belong to a session AutoBot started; a fresh ticket that happens to match an
    // old pull request must not be closed or cleared.
    if (state && config.pollGithub && pullRequest) {
      if (pullRequest.state === "MERGED") {
        actions.push({ kind: "finish", ticket, pullRequest });
        continue;
      }
      if (pullRequest.state === "CLOSED") {
        actions.push({ kind: "abandon", ticket, pullRequest });
        continue;
      }
    }

    if (config.pollJira && !state) {
      actions.push({ kind: "start", ticket });
      continue;
    }

    // Oldest unhandled item wins: a burst is answered one per tick, in the order it was written, and a
    // failed item stays at the head because its watermark was never advanced.
    const review =
      config.pollGithub && pullRequest
        ? nextReview(githubItem?.pendingReviews ?? [], state?.last_review_at, state?.last_review_id)
        : null;
    const comment =
      config.pollJira && state
        ? (ticket.pendingComments.find((candidate) =>
            isNewerCommentId(candidate.id, state.last_comment_id),
          ) ?? null)
        : null;

    if (review && comment && pullRequest) {
      if (comment.created <= review.submittedAt) {
        actions.push({ kind: "continue", ticket, comment });
      } else {
        actions.push({ kind: "review", ticket, pullRequest, review });
      }
      continue;
    }
    if (review && pullRequest) {
      actions.push({ kind: "review", ticket, pullRequest, review });
      continue;
    }
    if (comment) {
      actions.push({ kind: "continue", ticket, comment });
      continue;
    }

    actions.push({ kind: "skip", ticket, reason: "nothing new" });
  }

  return actions;
}
