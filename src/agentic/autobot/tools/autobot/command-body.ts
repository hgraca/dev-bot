/**
 * The prompt that starts an AutoBot run.
 *
 * A slash command is not portable. `opencode2 run "/devbot:stats"` sends that literal text to the
 * model (verified — the stored user message is the slash string, not the command body). AutoBot
 * therefore sends the command's own body as the prompt, with the ticket substituted — one source of
 * truth that reaches the agent on every host, and no id to get wrong.
 */

/** Drop a leading YAML frontmatter block, leaving the body. */
export function stripFrontmatter(markdown: string): string {
    const text = markdown.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
    if (!text.startsWith("---")) return text.trim();
    const end = text.indexOf("\n---", 3);
    if (end === -1) return text.trim();
    const body = text.slice(end + 4).replace(/^\n+/, "");
    return body.trim();
}

/**
 * The command body with `$ARGUMENTS` replaced by the ticket key.
 *
 * A body without the placeholder gets the key appended, so a reworded command cannot silently drop
 * the ticket it was started for.
 */
export function renderCommand(body: string, arguments_: string): string {
    const trimmed = body.trim();
    if (trimmed === "") return arguments_.trim();
    if (trimmed.includes("$ARGUMENTS")) {
        return trimmed.replaceAll("$ARGUMENTS", arguments_.trim());
    }
    return `${trimmed}\n\nTicket: ${arguments_.trim()}`;
}
