/**
 * Housekeeping for opencode sessions AutoBot no longer needs.
 *
 * A session is an orphan when no ticket's state names it and it is older than the grace window. The
 * age guard is not cosmetic: `start` writes the state only after the agent returns, so a session
 * created seconds ago is legitimately unreferenced for as long as its first run takes.
 *
 * Deleting a session does not shrink `opencode.db`, which is the file that actually grows, so a
 * vacuum follows the deletions.
 */

export interface SessionSummary {
    id: string;
    /** ISO timestamp of the session's last activity. */
    updatedAt: string;
}

export interface CleanupReport {
    deleted: string[];
    kept: number;
}

export const DEFAULT_MIN_AGE_HOURS = 24;

/** Sessions that no ticket references and that are past the grace window. */
export function selectOrphans(
    sessions: SessionSummary[],
    referenced: Set<string>,
    now: Date,
    minAgeHours: number = DEFAULT_MIN_AGE_HOURS,
): string[] {
    const threshold = now.getTime() - minAgeHours * 60 * 60 * 1000;
    return sessions
        .filter((session) => !referenced.has(session.id))
        .filter((session) => {
            const updated = Date.parse(session.updatedAt);
            // An unreadable timestamp is kept: deleting on missing evidence is the wrong default.
            return Number.isFinite(updated) && updated < threshold;
        })
        .map((session) => session.id);
}

export interface CleanupDeps {
    sessions: SessionSummary[];
    referenced: Set<string>;
    now: Date;
    minAgeHours?: number;
    deleteSession(id: string): Promise<void>;
    /** Records the space freed by the deletions; optional so a dry run can skip it. */
    vacuum?(): Promise<void>;
}

export async function cleanupSessions(
    deps: CleanupDeps,
): Promise<CleanupReport> {
    const orphans = selectOrphans(
        deps.sessions,
        deps.referenced,
        deps.now,
        deps.minAgeHours,
    );
    for (const id of orphans) {
        await deps.deleteSession(id);
    }
    if (orphans.length > 0 && deps.vacuum) {
        await deps.vacuum();
    }
    return { deleted: orphans, kept: deps.sessions.length - orphans.length };
}
