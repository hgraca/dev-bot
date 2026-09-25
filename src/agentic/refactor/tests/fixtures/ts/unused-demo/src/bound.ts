export function bound(first: string, spare: string): string {
  return first;
}

const rebound = bound.bind(null);

export const later = rebound("a", "b");
