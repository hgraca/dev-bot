/**
 * The Slack edge: one direct message between the bot and one person.
 *
 * Pure parsing is separated from the HTTP calls so the parts that can drift — Slack's envelope shape,
 * timestamp arithmetic — are asserted by tests rather than observed by hand. Every call funnels
 * through `call`, which turns `{ok:false, error}` into a thrown error: a silently ignored Slack
 * failure is a message the user never saw.
 */

/** A message read back from the direct message. */
export interface SlackMessage {
    /** Slack's own timestamp, which is also the ordering key. */
    ts: string;
    /** The author's user id; a bot message has none. */
    userId: string;
    text: string;
    /** Set when the message is a reply inside a thread. */
    threadTs?: string;
}

export interface SlackTransport {
    /** The user id behind an email address. */
    resolveUser(email: string): Promise<string>;
    /** The direct-message channel id for a user. */
    openDm(userId: string): Promise<string>;
    /** Post text, optionally inside a thread; returns the message timestamp. */
    post(channel: string, text: string, threadTs?: string): Promise<string>;
    /** Messages newer than `oldest`, oldest first. */
    history(channel: string, oldest?: string): Promise<SlackMessage[]>;
    /**
     * The replies inside one message's thread, oldest first.
     *
     * `conversations.history` returns only top-level messages, so a reply posted in a thread — the
     * normal way to answer a question — is invisible without this call.
     */
    replies(channel: string, threadTs: string): Promise<SlackMessage[]>;
}

export interface SlackCredentials {
    token: string;
    /** The one person the bot talks to. */
    email: string;
}

/** Slack answers with `{ok:false, error}`; treat it as a failure rather than reading an empty body. */
function readOk(payload: unknown, what: string): Record<string, unknown> {
    if (
        payload === null ||
        typeof payload !== "object" ||
        Array.isArray(payload)
    ) {
        throw new Error(
            `slack ${what}: expected an object, got ${typeof payload}`,
        );
    }
    const record = payload as Record<string, unknown>;
    if (record.ok !== true) {
        const error =
            typeof record.error === "string" ? record.error : "unknown error";
        throw new Error(`slack ${what} failed: ${error}`);
    }
    return record;
}

/** `users.lookupByEmail` → the account's user id. */
export function readUserId(payload: unknown): string {
    const record = readOk(payload, "users.lookupByEmail");
    const user = record.user as Record<string, unknown> | undefined;
    const id = user?.id;
    if (typeof id !== "string" || id === "") {
        throw new Error(
            "slack users.lookupByEmail: no user id in the response",
        );
    }
    return id;
}

/** `conversations.open` → the direct-message channel id. */
export function readChannelId(payload: unknown): string {
    const record = readOk(payload, "conversations.open");
    const channel = record.channel as Record<string, unknown> | undefined;
    const id = channel?.id;
    if (typeof id !== "string" || id === "") {
        throw new Error(
            "slack conversations.open: no channel id in the response",
        );
    }
    return id;
}

/** `chat.postMessage` → the posted message's timestamp. */
export function readTs(payload: unknown): string {
    const record = readOk(payload, "chat.postMessage");
    const ts = record.ts;
    if (typeof ts !== "string" || ts === "") {
        throw new Error("slack chat.postMessage: no timestamp in the response");
    }
    return ts;
}

/**
 * `conversations.history` → messages, oldest first.
 *
 * A message without a usable `ts` or `user` is dropped rather than defaulted: a reply has to be
 * attributed and ordered to be routed, and a guess would attribute it to the wrong person.
 */
export function readMessages(payload: unknown): SlackMessage[] {
    return readPage(payload, "conversations.history").messages;
}

/**
 * The replies that are still to be handled: from the configured person, newer than the watermark.
 *
 * Filtering by author is the whole self-filter. The bot's own messages carry no `user`, and anything
 * from another account is ignored, so a shared workspace cannot talk to a machine's AutoBot.
 */
export function repliesFrom(
    messages: SlackMessage[],
    userId: string,
    afterTs: string | undefined,
): SlackMessage[] {
    const floor = afterTs === undefined ? -1 : Number(afterTs);
    return messages.filter(
        (message) =>
            message.userId === userId &&
            Number(message.ts) > (Number.isNaN(floor) ? -1 : floor),
    );
}

/** One page of `conversations.history`/`conversations.replies`, with the cursor to continue. */
export function readPage(
    payload: unknown,
    what: string,
): { messages: SlackMessage[]; cursor?: string } {
    const record = readOk(payload, what);
    const raw = record.messages;
    const meta = record.response_metadata as
        Record<string, unknown> | undefined;
    const cursor =
        typeof meta?.next_cursor === "string" && meta.next_cursor !== ""
            ? meta.next_cursor
            : undefined;
    if (!Array.isArray(raw))
        return { messages: [], ...(cursor === undefined ? {} : { cursor }) };
    const messages: SlackMessage[] = [];
    for (const item of raw) {
        if (item === null || typeof item !== "object") continue;
        const message = item as Record<string, unknown>;
        const ts = typeof message.ts === "string" ? message.ts : "";
        const userId = typeof message.user === "string" ? message.user : "";
        if (ts === "" || userId === "") continue;
        const threadTs =
            typeof message.thread_ts === "string"
                ? message.thread_ts
                : undefined;
        messages.push({
            ts,
            userId,
            text: typeof message.text === "string" ? message.text : "",
            ...(threadTs === undefined ? {} : { threadTs }),
        });
    }
    // Slack answers newest first; the caller wants the order the conversation happened in.
    messages.sort((a, b) => (a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : 0));
    return { messages, ...(cursor === undefined ? {} : { cursor }) };
}

export function createSlackClient(token: string): SlackTransport {
    const authorization = `Bearer ${token}`;

    async function call(
        method: string,
        body: Record<string, unknown>,
    ): Promise<unknown> {
        const response = await fetch(`https://slack.com/api/${method}`, {
            method: "POST",
            headers: {
                Authorization: authorization,
                "Content-Type": "application/json; charset=utf-8",
            },
            body: JSON.stringify(body),
        });
        if (!response.ok) {
            throw new Error(`slack ${method} failed: HTTP ${response.status}`);
        }
        return response.json();
    }

    return {
        async resolveUser(email: string): Promise<string> {
            return readUserId(await call("users.lookupByEmail", { email }));
        },

        async openDm(userId: string): Promise<string> {
            return readChannelId(
                await call("conversations.open", { users: userId }),
            );
        },

        async post(
            channel: string,
            text: string,
            threadTs?: string,
        ): Promise<string> {
            return readTs(
                await call("chat.postMessage", {
                    channel,
                    text,
                    ...(threadTs === undefined ? {} : { thread_ts: threadTs }),
                }),
            );
        },

        async history(
            channel: string,
            oldest?: string,
        ): Promise<SlackMessage[]> {
            // A tick that follows a quiet night can see more than one page; stopping at the first would
            // advance the watermark past the rest and drop replies forever.
            const collected: SlackMessage[] = [];
            let cursor: string | undefined;
            for (let page = 0; page < 20; page += 1) {
                const parsed = readPage(
                    await call("conversations.history", {
                        channel,
                        limit: 200,
                        ...(oldest === undefined ? {} : { oldest }),
                        ...(cursor === undefined ? {} : { cursor }),
                    }),
                    "conversations.history",
                );
                collected.push(...parsed.messages);
                cursor = parsed.cursor;
                if (cursor === undefined) break;
            }
            // Returning a partial page would advance the watermark past replies never read, and they
            // would be lost for good. Failing keeps the watermark where it is.
            if (cursor !== undefined) {
                throw new Error(
                    "slack conversations.history: more than 20 pages — refusing a partial read",
                );
            }
            return collected;
        },

        async replies(
            channel: string,
            threadTs: string,
        ): Promise<SlackMessage[]> {
            const parsed = readPage(
                await call("conversations.replies", {
                    channel,
                    ts: threadTs,
                    limit: 200,
                }),
                "conversations.replies",
            );
            // The thread's first message is the question itself, not a reply to it.
            return parsed.messages.filter((message) => message.ts !== threadTs);
        },
    };
}
