const CONFIG_KEYS = ["name", "description", "docs_url", "category", "order"];
const IGNORED_KEYS = ["$schema"];

export function titleCase(raw) {
  if (typeof raw !== "string" || raw === "") return "";
  return raw
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(" ");
}

export function manifestDisplayName(packageName) {
  if (typeof packageName !== "string" || packageName === "") return "";
  return titleCase(packageName.split("/").pop());
}

export function resolveName(configName, manifestName, repoName) {
  if (typeof configName === "string" && configName.trim() !== "") return configName.trim();
  if (typeof manifestName === "string" && manifestName.trim() !== "") return manifestName.trim();
  return titleCase(repoName);
}

function isAbsoluteHttpUrl(value) {
  if (typeof value !== "string" || value === "") return false;
  let url;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  return url.protocol === "http:" || url.protocol === "https:";
}

export function validateConfig(config) {
  if (config === null || typeof config !== "object" || Array.isArray(config)) {
    return { ok: false, errors: ["config must be a JSON object"] };
  }

  const errors = [];

  if (typeof config.description !== "string" || config.description.trim() === "") {
    errors.push("description is required and must be a non-empty string");
  }
  if (!isAbsoluteHttpUrl(config.docs_url)) {
    errors.push("docs_url is required and must be an absolute http(s) URL");
  }
  if (config.name !== undefined && (typeof config.name !== "string" || config.name.trim() === "")) {
    errors.push("name must be a non-empty string when present");
  }
  if (config.category !== undefined && typeof config.category !== "string") {
    errors.push("category must be a string when present");
  }
  if (config.order !== undefined && typeof config.order !== "number") {
    errors.push("order must be a number when present");
  }
  for (const key of Object.keys(config)) {
    if (!CONFIG_KEYS.includes(key) && !IGNORED_KEYS.includes(key)) errors.push(`unknown key: ${key}`);
  }

  return { ok: errors.length === 0, errors };
}

export function toEntry({ repo, config, manifestName }) {
  const entry = {
    repo,
    name: resolveName(config.name, manifestName, repo),
    description: config.description,
    docs_url: new URL(config.docs_url).href,
  };
  if (config.category !== undefined) entry.category = config.category;
  if (config.order !== undefined) entry.order = config.order;
  return entry;
}

export function sortProjects(entries) {
  return entries.slice().sort((a, b) => {
    const orderA = a.order ?? Infinity;
    const orderB = b.order ?? Infinity;
    if (orderA !== orderB) return orderA - orderB;
    return String(a.name).localeCompare(String(b.name));
  });
}
