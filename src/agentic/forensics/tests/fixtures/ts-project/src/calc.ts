export class Calc {
  add(a: number, b: number): number {
    return a + b;
  }

  classify(n: number): string {
    if (n < 0) {
      return 'negative';
    }
    if (n === 0) {
      return 'zero';
    }
    return 'positive';
  }
}

export function pick(n: number): number {
  return n > 0 ? 1 : 0;
}
