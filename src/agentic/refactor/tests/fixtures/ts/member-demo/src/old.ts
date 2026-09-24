export function scale(): number {
  return 2;
}

export class Old {
  static _v = 1;

  static make(x: number): string {
    return String(x);
  }

  /**
   * Return the input unchanged.
   */
  static ping(n: number): number {
    return n <= 0 ? 0 : Old.ping(n - 1) + Old._v;
  }

  static countdown(n: number): number {
    return n <= 0 ? 0 : Old.countdown(n - 1);
  }

  static measured(): number {
    return scale();
  }

  get size(): number {
    return Old._v;
  }

  set size(v: number) {
    Old._v = v;
  }

  instanceOnly(): string {
    return "instance";
  }
}
