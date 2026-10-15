import { test } from "node:test";
import assert from "node:assert/strict";

import {
  titleCase,
  manifestDisplayName,
  resolveName,
  validateConfig,
  toEntry,
  sortProjects,
} from "./umbrella.mjs";

test("titleCase title-cases hyphen and underscore separated words", () => {
  assert.equal(titleCase("transfers"), "Transfers");
  assert.equal(titleCase("dev-bot"), "Dev Bot");
  assert.equal(titleCase("hotels_api"), "Hotels Api");
  assert.equal(titleCase(""), "");
});

test("manifestDisplayName strips the owner/scope prefix", () => {
  assert.equal(manifestDisplayName("acme/transfers"), "Transfers");
  assert.equal(manifestDisplayName("@acme/transfers"), "Transfers");
  assert.equal(manifestDisplayName("acme/dev-bot"), "Dev Bot");
  assert.equal(manifestDisplayName("transfers"), "Transfers");
  assert.equal(manifestDisplayName(undefined), "");
  assert.equal(manifestDisplayName(null), "");
  assert.equal(manifestDisplayName(""), "");
});

test("resolveName prefers the config name, then the manifest, then the repo", () => {
  assert.equal(resolveName("Transfers", "Ignored", "core"), "Transfers");
  assert.equal(resolveName("", "Transfers", "core"), "Transfers");
  assert.equal(resolveName(undefined, "Transfers", "core"), "Transfers");
  assert.equal(resolveName(null, null, "core"), "Core");
  assert.equal(resolveName(undefined, "", "audit-log"), "Audit Log");
});

test("validateConfig accepts a minimal valid config", () => {
  const result = validateConfig({
    description: "Taxi portal backend",
    docs_url: "https://acme.github.io/core/v1/",
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.errors, []);
});

test("validateConfig accepts every optional field", () => {
  const result = validateConfig({
    name: "Transfers",
    description: "Taxi portal backend",
    docs_url: "https://acme.github.io/core/v1/",
    category: "Backend",
    order: 10,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.errors, []);
});

test("validateConfig rejects the retired logo key", () => {
  const result = validateConfig({
    description: "d",
    docs_url: "https://example.com/",
    logo: "https://example.com/logo.svg",
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("logo")));
});

test("validateConfig allows http as well as https", () => {
  const result = validateConfig({ description: "d", docs_url: "http://localhost:4000/" });
  assert.equal(result.ok, true);
});

test("validateConfig allows a $schema pointer and does not copy it into entries", () => {
  const config = {
    $schema: "https://acme.github.io/umbrella-integration.schema.json",
    description: "d",
    docs_url: "https://example.com/",
  };
  assert.equal(validateConfig(config).ok, true);
  assert.equal("$schema" in toEntry({ repo: "core", config, manifestName: "" }), false);
});

test("validateConfig reports a missing description", () => {
  const result = validateConfig({ docs_url: "https://example.com/" });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("description")));
});

test("validateConfig reports a missing docs_url", () => {
  const result = validateConfig({ description: "d" });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("docs_url")));
});

test("validateConfig rejects a non-absolute docs_url", () => {
  for (const bad of ["not-a-url", "/relative/path", ""]) {
    const result = validateConfig({ description: "d", docs_url: bad });
    assert.equal(result.ok, false, `expected ${JSON.stringify(bad)} to be rejected`);
  }
});

test("validateConfig rejects a non-string description", () => {
  const result = validateConfig({ description: 123, docs_url: "https://example.com/" });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("description")));
});

test("validateConfig rejects a non-string name", () => {
  const result = validateConfig({ name: 5, description: "d", docs_url: "https://example.com/" });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("name")));
});

test("validateConfig rejects a non-numeric order", () => {
  const result = validateConfig({ description: "d", docs_url: "https://example.com/", order: "1" });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("order")));
});

test("validateConfig rejects unknown keys", () => {
  const result = validateConfig({
    description: "d",
    docs_url: "https://example.com/",
    unexpected: true,
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((e) => e.includes("unexpected")));
});

test("validateConfig rejects a non-object payload", () => {
  for (const bad of [null, undefined, "x", 42, []]) {
    assert.equal(validateConfig(bad).ok, false);
  }
});

test("toEntry resolves the name and drops absent optional fields", () => {
  const entry = toEntry({
    repo: "core",
    config: { description: "Taxi portal backend", docs_url: "https://acme.github.io/core/v1/" },
    manifestName: "Transfers",
  });
  assert.deepEqual(entry, {
    repo: "core",
    name: "Transfers",
    description: "Taxi portal backend",
    docs_url: "https://acme.github.io/core/v1/",
  });
  assert.equal("category" in entry, false);
  assert.equal("order" in entry, false);
  assert.equal("logo" in entry, false);
});

test("toEntry normalises the docs_url", () => {
  const entry = toEntry({
    repo: "core",
    config: { description: "d", docs_url: "https://Example.COM/V1/" },
    manifestName: "",
  });
  assert.equal(entry.docs_url, "https://example.com/V1/");
});

test("toEntry cannot emit a docs_url that breaks out of the href attribute", () => {
  const entry = toEntry({
    repo: "evil",
    config: { description: "d", docs_url: 'https://evil.example/"><img src=x onerror=alert(1)>' },
    manifestName: "",
  });
  assert.equal(entry.docs_url.includes('"'), false);
  assert.equal(entry.docs_url.includes("<"), false);
});

test("toEntry keeps the optional fields when present", () => {
  const entry = toEntry({
    repo: "core",
    config: {
      name: "Transfers",
      description: "d",
      docs_url: "https://example.com/",
      category: "Backend",
      order: 1,
    },
    manifestName: "Ignored",
  });
  assert.deepEqual(entry, {
    repo: "core",
    name: "Transfers",
    description: "d",
    docs_url: "https://example.com/",
    category: "Backend",
    order: 1,
  });
});

test("sortProjects orders by order ascending, then by name", () => {
  const sorted = sortProjects([
    { name: "Zeta", order: 1 },
    { name: "Alpha", order: 2 },
    { name: "Beta", order: 1 },
  ]);
  assert.deepEqual(sorted.map((p) => p.name), ["Beta", "Zeta", "Alpha"]);
});

test("sortProjects places entries without an order last", () => {
  const sorted = sortProjects([
    { name: "NoOrder" },
    { name: "HasOrder", order: 5 },
  ]);
  assert.deepEqual(sorted.map((p) => p.name), ["HasOrder", "NoOrder"]);
});

test("sortProjects does not mutate the input array", () => {
  const input = [{ name: "B", order: 2 }, { name: "A", order: 1 }];
  const snapshot = input.slice();
  sortProjects(input);
  assert.deepEqual(input, snapshot);
});
