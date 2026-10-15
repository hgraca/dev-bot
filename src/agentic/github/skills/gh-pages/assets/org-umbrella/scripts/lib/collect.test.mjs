import { test } from "node:test";
import assert from "node:assert/strict";

import { collectProjects } from "./collect.mjs";

const API = "https://api.test";
const listUrl = `${API}/orgs/ACME/repos?per_page=100&type=all`;
const configUrl = (repo, branch = "main") =>
  `${API}/repos/ACME/${repo}/contents/docs/umbrella-integration.json?ref=${branch}`;
const manifestUrl = (repo, file, branch = "main") =>
  `${API}/repos/ACME/${repo}/contents/${file}?ref=${branch}`;

function res(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
    json: async () => (typeof body === "string" ? JSON.parse(body) : body),
    headers: { get: () => null },
  };
}

function fetchFrom(routes) {
  return async (url) => (url in routes ? routes[url] : res(404, {}));
}

function collect(routes, extra = {}) {
  return collectProjects({ org: "ACME", fetchFn: fetchFrom(routes), apiBase: API, ...extra });
}

test("collectProjects includes repos with a valid config and skips the rest", async () => {
  const projects = await collect({
    [listUrl]: res(200, [
      { name: "core", default_branch: "main" },
      { name: "other", default_branch: "main" },
    ]),
    [configUrl("core")]: res(200, {
      description: "Taxi portal backend",
      docs_url: "https://acme.github.io/core/v1/",
    }),
  });

  assert.equal(projects.length, 1);
  assert.equal(projects[0].repo, "core");
  assert.equal(projects[0].name, "Core");
});

test("collectProjects infers the name from the manifest when the config omits it", async () => {
  const projects = await collect({
    [listUrl]: res(200, [{ name: "core", default_branch: "main" }]),
    [configUrl("core")]: res(200, { description: "d", docs_url: "https://x.example/" }),
    [manifestUrl("core", "composer.json")]: res(200, { name: "acme/transfers" }),
  });

  assert.equal(projects[0].name, "Transfers");
});

test("collectProjects lets the config name override the manifest", async () => {
  const projects = await collect({
    [listUrl]: res(200, [{ name: "core", default_branch: "main" }]),
    [configUrl("core")]: res(200, {
      name: "Transfers",
      description: "d",
      docs_url: "https://x.example/",
    }),
    [manifestUrl("core", "composer.json")]: res(200, { name: "acme/ignored" }),
  });

  assert.equal(projects[0].name, "Transfers");
});

test("collectProjects falls back to package.json for the manifest name", async () => {
  const projects = await collect({
    [listUrl]: res(200, [{ name: "web", default_branch: "main" }]),
    [configUrl("web")]: res(200, { description: "d", docs_url: "https://x.example/" }),
    [manifestUrl("web", "package.json")]: res(200, { name: "acme/web-portal" }),
  });

  assert.equal(projects[0].name, "Web Portal");
});

test("collectProjects warns when a manifest fetch fails for a non-404 reason", async () => {
  const warnings = [];
  const projects = await collect(
    {
      [listUrl]: res(200, [{ name: "web", default_branch: "main" }]),
      [configUrl("web")]: res(200, { description: "d", docs_url: "https://x.example/" }),
      [manifestUrl("web", "composer.json")]: res(500, { message: "boom" }),
      [manifestUrl("web", "package.json")]: res(200, { name: "acme/web-portal" }),
    },
    { warn: (m) => warnings.push(m) },
  );

  assert.equal(projects[0].name, "Web Portal");
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /web/);
  assert.match(warnings[0], /500/);
});

test("collectProjects warns and skips a config that fails validation", async () => {
  const warnings = [];
  const projects = await collect(
    {
      [listUrl]: res(200, [{ name: "bad", default_branch: "main" }]),
      [configUrl("bad")]: res(200, { description: "d" }),
    },
    { warn: (m) => warnings.push(m) },
  );

  assert.deepEqual(projects, []);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /bad/);
});

test("collectProjects warns and skips a config that is not valid JSON", async () => {
  const warnings = [];
  const projects = await collect(
    {
      [listUrl]: res(200, [{ name: "broken", default_branch: "main" }]),
      [configUrl("broken")]: res(200, "{ not json"),
    },
    { warn: (m) => warnings.push(m) },
  );

  assert.deepEqual(projects, []);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /broken/);
});

test("collectProjects skips archived repos", async () => {
  const projects = await collect({
    [listUrl]: res(200, [
      { name: "old", default_branch: "main", archived: true },
      { name: "live", default_branch: "main" },
    ]),
    [configUrl("old")]: res(200, { description: "d", docs_url: "https://x.example/" }),
    [configUrl("live")]: res(200, { description: "d", docs_url: "https://y.example/" }),
  });

  assert.deepEqual(projects.map((p) => p.repo), ["live"]);
});

test("collectProjects returns entries sorted by order then name", async () => {
  const projects = await collect({
    [listUrl]: res(200, [
      { name: "b", default_branch: "main" },
      { name: "a", default_branch: "main" },
    ]),
    [configUrl("a")]: res(200, { name: "Alpha", description: "d", docs_url: "https://x/" }),
    [configUrl("b")]: res(200, { name: "Beta", order: 1, description: "d", docs_url: "https://x/" }),
  });

  assert.deepEqual(projects.map((p) => p.name), ["Beta", "Alpha"]);
});

test("collectProjects throws when the repo listing fails", async () => {
  await assert.rejects(
    () => collect({ [listUrl]: res(403, { message: "rate limited" }) }),
    /403/,
  );
});

test("collectProjects follows pagination across pages", async () => {
  const page1 = Array.from({ length: 100 }, (_, i) => ({ name: `repo-${i}`, default_branch: "main" }));
  const secondPageUrl = `${listUrl}&page=2`;

  const projects = await collect({
    [listUrl]: res(200, page1),
    [secondPageUrl]: res(200, [{ name: "core", default_branch: "main" }]),
    [configUrl("core")]: res(200, { name: "Transfers", description: "d", docs_url: "https://x/" }),
  });

  assert.deepEqual(projects.map((p) => p.name), ["Transfers"]);
});

test("collectProjects warns and skips when a config fetch fails with a non-404 error", async () => {
  const warnings = [];
  const projects = await collect(
    {
      [listUrl]: res(200, [{ name: "flaky", default_branch: "main" }]),
      [configUrl("flaky")]: res(500, { message: "boom" }),
    },
    { warn: (m) => warnings.push(m) },
  );

  assert.deepEqual(projects, []);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /flaky/);
  assert.match(warnings[0], /500/);
});
