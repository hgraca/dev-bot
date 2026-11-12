import { describe, expect, test } from "bun:test";

import { isSigned, sign } from "./signature.ts";

describe("sign", () => {
  test("appends the signature", () => {
    expect(sign("hello")).toBe("hello\n\nauthored by AutoBot");
  });

  test("is idempotent", () => {
    const once = sign("hello");
    expect(sign(once)).toBe(once);
  });

  test("tolerates trailing whitespace", () => {
    expect(sign("hello  \n")).toBe("hello\n\nauthored by AutoBot");
  });
});

describe("isSigned", () => {
  test("recognises a signed body", () => {
    expect(isSigned("hello\n\nauthored by AutoBot")).toBe(true);
  });

  test("recognises a signed body with trailing whitespace", () => {
    expect(isSigned("hello\n\nauthored by AutoBot\n")).toBe(true);
  });

  test("rejects an unsigned body", () => {
    expect(isSigned("hello")).toBe(false);
  });

  test("rejects the signature in the middle", () => {
    expect(isSigned("authored by AutoBot\n\nbut then more text")).toBe(false);
  });
});
