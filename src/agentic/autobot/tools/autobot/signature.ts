/**
 * The marker every AutoBot comment carries.
 *
 * It is not decoration: with no separate bot identity, a comment's author cannot tell AutoBot's reply
 * from a human's. The signature is what does — a signed comment is AutoBot's and is never a candidate
 * for a follow-up, so the module cannot answer itself.
 */

export const SIGNATURE = "authored by AutoBot";

/** Append the signature unless it is already the last line. */
export function sign(body: string): string {
  const trimmed = body.replace(/\s+$/, "");
  return trimmed.endsWith(SIGNATURE) ? trimmed : `${trimmed}\n\n${SIGNATURE}`;
}

/** True when AutoBot wrote the body. */
export function isSigned(body: string): boolean {
  return body.trimEnd().endsWith(SIGNATURE);
}
