/**
 * Reading AutoBot's pull requests out of GitHub.
 *
 * As with Jira, the transport is injected: `gh` is a process, not something worth faking, so the
 * selection rules and the review comparison live here and are unit-tested.
 *
 * A ticket with no pull request is a normal result, not an error — the session may still be working.
 */

export type PullRequestState = "OPEN" | "MERGED" | "CLOSED";

export interface GhReview {
    id: string;
    authorLogin: string;
    body: string;
    submittedAt: string;
}

export interface GhPullRequest {
    number: number;
    url: string;
    state: PullRequestState;
    reviews: GhReview[];
}

export interface GhTicket {
    key: string;
    /** The configured connection that found the ticket; two sites can share an issue key. */
    connection?: string;
}

export interface GithubPollItem {
    key: string;
    connection?: string;
    pullRequest: GhPullRequest | null;
    /** Human reviews, oldest first. Every one must be addressed, not only the newest. */
    pendingReviews: GhReview[];
}

export interface GhTransport {
    /** Pull requests whose title carries the ticket key. */
    findPullRequests(
        ticketKey: string,
        connection?: string,
    ): Promise<GhPullRequest[]>;
}

const STATE_PRIORITY: Record<PullRequestState, number> = {
    MERGED: 3,
    OPEN: 2,
    CLOSED: 1,
};

/**
 * The pull request that belongs to this ticket: the most advanced state wins, then the highest number.
 */
export function selectPullRequest(
    pullRequests: GhPullRequest[],
): GhPullRequest | null {
    if (pullRequests.length === 0) return null;
    return [...pullRequests].sort((a, b) => {
        const byState = STATE_PRIORITY[b.state] - STATE_PRIORITY[a.state];
        return byState !== 0 ? byState : b.number - a.number;
    })[0];
}

/**
 * Human reviews in submission order, so a burst is addressed one per tick. The sort is stable, so
 * reviews submitted in the same second keep the order GitHub returned — a deterministic tie-break.
 */
/**
 * Reviews in submission order, so a burst is addressed one per tick. No author filter is needed:
 * AutoBot pushes commits rather than submitting reviews, and the stable sort keeps GitHub's order for
 * equal timestamps — a deterministic tie-break.
 */
export function orderedReviews(reviews: GhReview[]): GhReview[] {
    return [...reviews].sort((a, b) =>
        a.submittedAt < b.submittedAt
            ? -1
            : a.submittedAt > b.submittedAt
              ? 1
              : 0,
    );
}

/** One poll pass over the tickets that carry a session. */
export async function pollGithub(options: {
    tickets: GhTicket[];
    transport: GhTransport;
}): Promise<GithubPollItem[]> {
    const { tickets, transport } = options;
    const items: GithubPollItem[] = [];
    for (const ticket of tickets) {
        const pullRequest = selectPullRequest(
            await transport.findPullRequests(ticket.key, ticket.connection),
        );
        items.push({
            key: ticket.key,
            connection: ticket.connection,
            pullRequest,
            pendingReviews: pullRequest
                ? orderedReviews(pullRequest.reviews)
                : [],
        });
    }
    return items;
}
