/**
 * The marker every AutoBot comment carries.
 *
 * It is not decoration: with no separate bot identity, a comment's author cannot tell AutoBot's reply
 * from a human's. The signature is what does — a signed comment is AutoBot's and is never a candidate
 * for a follow-up, so the module cannot answer itself.
 */

export const SIGNATURE = "authored by AutoBot";

/** Append the signature unless it is already the final line. */
export function sign(body: string): string {
  const trimmed = body.replace(/\s+$/, "");
  return isSigned(trimmed) ? trimmed : `${trimmed}\n\n${SIGNATURE}`;
}

/**
 * True when AutoBot wrote the body: the signature is its own final line, not merely text that happens
 * to end with the same words. Otherwise a human writing "why did you say authored by AutoBot" would
 * be filtered out and never reach the agent.
 */
export function isSigned(body: string): boolean {
  const trimmed = body.trimEnd();
  return trimmed === SIGNATURE || trimmed.endsWith(`\n${SIGNATURE}`);
}
