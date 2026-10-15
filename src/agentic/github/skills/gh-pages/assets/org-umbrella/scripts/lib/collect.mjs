import { manifestDisplayName, validateConfig, toEntry, sortProjects } from "./umbrella.mjs";

const CONFIG_PATH = "docs/umbrella-integration.json";
const MANIFEST_PATHS = ["composer.json", "package.json"];
const PER_PAGE = 100;

function authHeaders(token) {
  return {
    Accept: "application/vnd.github+json",
    "User-Agent": "docs-umbrella",
    "X-GitHub-Api-Version": "2022-11-28",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

async function listRepos({ org, fetchFn, apiBase, token }) {
  const repos = [];
  let page = 1;
  for (;;) {
    const base = `${apiBase}/orgs/${org}/repos?per_page=${PER_PAGE}&type=all`;
    const url = page === 1 ? base : `${base}&page=${page}`;
    const res = await fetchFn(url, { headers: authHeaders(token) });
    if (!res.ok) throw new Error(`failed to list repos for ${org}: HTTP ${res.status}`);
    const batch = await res.json();
    repos.push(...batch);
    if (batch.length < PER_PAGE) break;
    page += 1;
  }
  return repos;
}

async function fetchFile({ fetchFn, apiBase, org, repo, branch, path, token }) {
  const url = `${apiBase}/repos/${org}/${repo}/contents/${path}?ref=${encodeURIComponent(branch)}`;
  const res = await fetchFn(url, {
    headers: { ...authHeaders(token), Accept: "application/vnd.github.raw" },
  });
  if (res.status === 404) return { found: false };
  if (!res.ok) return { found: false, error: `HTTP ${res.status}` };
  return { found: true, body: await res.text() };
}

async function resolveManifestName({ fetchFn, apiBase, org, repo, branch, token, warn }) {
  for (const path of MANIFEST_PATHS) {
    const file = await fetchFile({ fetchFn, apiBase, org, repo, branch, path, token });
    if (!file.found) {
      if (file.error) warn(`${repo}: could not read ${path} (${file.error})`);
      continue;
    }
    try {
      const pkg = JSON.parse(file.body);
      if (typeof pkg.name === "string" && pkg.name.trim() !== "") {
        return manifestDisplayName(pkg.name);
      }
    } catch {
      // malformed manifest — fall through to the next candidate
    }
  }
  return "";
}

export async function collectProjects({
  org,
  fetchFn,
  apiBase = "https://api.github.com",
  token,
  warn = () => {},
}) {
  const repos = await listRepos({ org, fetchFn, apiBase, token });
  const projects = [];

  for (const repo of repos) {
    if (repo.archived || repo.disabled) continue;

    const branch = repo.default_branch || "main";
    const where = { fetchFn, apiBase, org, repo: repo.name, branch, token, warn };

    const file = await fetchFile({ ...where, path: CONFIG_PATH });
    if (!file.found) {
      if (file.error) warn(`${repo.name}: could not read ${CONFIG_PATH} (${file.error})`);
      continue;
    }

    let config;
    try {
      config = JSON.parse(file.body);
    } catch {
      warn(`${repo.name}: ${CONFIG_PATH} is not valid JSON — skipped`);
      continue;
    }

    const { ok, errors } = validateConfig(config);
    if (!ok) {
      warn(`${repo.name}: invalid ${CONFIG_PATH} — ${errors.join("; ")}`);
      continue;
    }

    const manifestName = config.name ? "" : await resolveManifestName(where);
    projects.push(toEntry({ repo: repo.name, config, manifestName }));
  }

  return sortProjects(projects);
}
