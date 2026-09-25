function audit(): number {
  return 1;
}

export function logged(first: string, spare = audit()): string {
  return first;
}

export const called = logged("x");

export function plain(first: string, unused = 5): string {
  return first;
}

export const plainCalled = plain("x");
