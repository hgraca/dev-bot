// Tests for the slot wiring: label, empty state, per-session value.
import {
    afterEach,
    describe,
    expect,
    mock,
    setSystemTime,
    test,
} from "bun:test";

type El = {
    tag: string;
    props: Record<string, unknown>;
    children: El[];
    text?: string;
};

// The TUI half cannot be driven headlessly, so the two display imports are
// mocked and the api is stubbed; the assertions are about what the row shows.
mock.module("@opentui/solid", () => {
    const textNode = (value: unknown): El => ({
        tag: "#text",
        props: {},
        children: [],
        text: String(value),
    });
    return {
        createElement: (tag: string): El => ({ tag, props: {}, children: [] }),
        createTextNode: textNode,
        // The value is rendered through a reactive accessor, and the row is rebuilt
        // from current state on every call, so resolving it here is enough.
        insert: (parent: El, child: unknown) => {
            const value =
                typeof child === "function"
                    ? (child as () => unknown)()
                    : child;
            for (const item of Array.isArray(value) ? value : [value]) {
                if (item && typeof item === "object")
                    parent.children.push(item as El);
                else if (typeof item === "string")
                    parent.children.push(textNode(item));
            }
        },
        insertNode: (parent: El, child: El) => {
            parent.children.push(child);
        },
        setProp: (el: El, key: string, value: unknown) => {
            el.props[key] = value;
        },
    };
});

mock.module("solid-js", () => ({
    createSignal: (init: unknown) => {
        let value = init;
        return [
            () => value,
            (next: unknown) => {
                value =
                    typeof next === "function"
                        ? (next as (prev: unknown) => unknown)(value)
                        : next;
            },
        ];
    },
}));

const { default: plugin } = await import("./index");

type Row = {
    slots: {
        sidebar_content: (_ctx: unknown, props: { session_id: string }) => El;
    };
};

function stubApi() {
    const handlers = new Map<string, (event: never) => void>();
    let slot: Row | null = null;
    const api = {
        event: {
            on: (type: string, handler: (event: never) => void) => {
                handlers.set(type, handler);
                return () => {};
            },
        },
        slots: {
            register: (def: Row) => {
                slot = def;
            },
        },
        theme: { current: {} },
    };
    const emit = (type: string, event: unknown) =>
        handlers.get(type)?.(event as never);
    const row = (sessionID = "ses_a") =>
        slot!.slots.sidebar_content(undefined, { session_id: sessionID });
    return {
        api,
        emit,
        label: () => row().children[0]!.children[0]!.text,
        value: (sessionID = "ses_a") =>
            row(sessionID).children[1]!.children[0]!.text,
    };
}

const assistant = (
    id: string,
    time: { created: number; completed?: number },
) => ({
    properties: { sessionID: "ses_a", info: { id, role: "assistant", time } },
});

const delta = (sessionID: string, messageID: string) => ({
    properties: {
        sessionID,
        messageID,
        partID: "p1",
        field: "text",
        delta: "x",
    },
});

afterEach(() => {
    setSystemTime();
});

describe("sidebar row", () => {
    test("shows the label and no value before a measurement", async () => {
        const stub = stubApi();
        await plugin.tui(stub.api as never);

        expect(stub.label()).toBe("TTFT");
        expect(stub.value()).toBe("-");
    });

    test("shows the first delta's time", async () => {
        const stub = stubApi();
        await plugin.tui(stub.api as never);

        setSystemTime(new Date(1_000));
        stub.emit("message.updated", assistant("m1", { created: 1_000 }));
        setSystemTime(new Date(2_200));
        stub.emit("message.part.delta", delta("ses_a", "m1"));

        expect(stub.value()).toBe("1.2s");
    });

    test("keeps each session's own reading", async () => {
        const stub = stubApi();
        await plugin.tui(stub.api as never);

        setSystemTime(new Date(1_000));
        stub.emit("message.updated", assistant("m1", { created: 1_000 }));
        setSystemTime(new Date(2_200));
        stub.emit("message.part.delta", delta("ses_b", "m1"));

        expect(stub.value("ses_b")).toBe("1.2s");
        expect(stub.value("ses_a")).toBe("-");
    });

    test("ignores a delta after the first one", async () => {
        const stub = stubApi();
        await plugin.tui(stub.api as never);

        setSystemTime(new Date(1_000));
        stub.emit("message.updated", assistant("m1", { created: 1_000 }));
        setSystemTime(new Date(2_200));
        stub.emit("message.part.delta", delta("ses_a", "m1"));
        // A step boundary re-emits the message without completing it.
        stub.emit("message.updated", assistant("m1", { created: 1_000 }));
        setSystemTime(new Date(31_000));
        stub.emit("message.part.delta", delta("ses_a", "m1"));

        expect(stub.value()).toBe("1.2s");
    });

    test("shows no value for a request that completed without a delta", async () => {
        const stub = stubApi();
        await plugin.tui(stub.api as never);

        stub.emit(
            "message.updated",
            assistant("m1", { created: 1_000, completed: 4_000 }),
        );
        setSystemTime(new Date(5_000));
        stub.emit("message.part.delta", delta("ses_a", "m1"));

        expect(stub.value()).toBe("-");
    });
});
