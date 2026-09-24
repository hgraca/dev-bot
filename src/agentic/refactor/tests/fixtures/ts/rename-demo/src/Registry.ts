/**
 * A reference held in a string: the type-aware rename cannot see it, so the
 * tool must report it rather than leave it behind silently.
 */
const HANDLERS: Record<string, string> = {
  primary: "greet",
};

export function handlerName(key: string): string {
  return HANDLERS[key] ?? "";
}
