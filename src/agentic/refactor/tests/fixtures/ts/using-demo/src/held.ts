declare const existing: { [Symbol.dispose](): void };

export function held(): number {
  using res = existing;
  return 0;
}
