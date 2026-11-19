import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { renderCommand, stripFrontmatter } from "./command-body.ts";

const COMMAND_FILE = join(
    import.meta.dir,
    "..",
    "..",
    "commands",
    "autobot-work.md",
);

describe("stripFrontmatter", () => {
    test("drops the YAML block and keeps the body", () => {
        const markdown = "---\nname: x\ndescription: y\n---\n\nBody line\n";
        expect(stripFrontmatter(markdown)).toBe("Body line");
    });

    test("leaves frontmatter-free text alone", () => {
        expect(stripFrontmatter("Just text\n")).toBe("Just text");
    });

    test("keeps a document whose frontmatter never closes", () => {
        expect(stripFrontmatter("---\nbroken")).toBe("---\nbroken");
    });

    test("normalises CRLF", () => {
        expect(stripFrontmatter("---\r\nname: x\r\n---\r\n\r\nBody\r\n")).toBe(
            "Body",
        );
    });
});

describe("renderCommand", () => {
    test("substitutes every $ARGUMENTS", () => {
        expect(renderCommand("Work $ARGUMENTS now, $ARGUMENTS", "ARC-1")).toBe(
            "Work ARC-1 now, ARC-1",
        );
    });

    test("appends the ticket when the body has no placeholder", () => {
        expect(renderCommand("Work the ticket.", "ARC-1")).toBe(
            "Work the ticket.\n\nTicket: ARC-1",
        );
    });

    test("an empty body degrades to the ticket alone", () => {
        expect(renderCommand("", "ARC-1")).toBe("ARC-1");
    });
});

describe("the shipped AutoBot command", () => {
    test("renders a prompt that names its skills and carries the ticket", () => {
        const body = stripFrontmatter(readFileSync(COMMAND_FILE, "utf8"));
        const prompt = renderCommand(body, "ARC-1017");

        expect(prompt).toContain("devbot:autobot-mode");
        expect(prompt).toContain("devbot:auto-dev");
        expect(prompt).toContain("Ticket: ARC-1017");
        expect(prompt).toContain("authored by AutoBot");
        // The placeholder must be gone, not merely appended next to.
        expect(prompt).not.toContain("$ARGUMENTS");
    });
});
