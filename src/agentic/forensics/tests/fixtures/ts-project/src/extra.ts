export const arrow = (x: number): number => {
  if (x > 0) {
    return 1;
  }
  return 0;
};

export const obj = {
  method(a: number): number {
    return a ? 1 : 0;
  },
};

export class Holder {
  get value(): number {
    return 1;
  }

  set value(v: number) {
    if (v < 0) {
      throw new Error('neg');
    }
  }

  handle = (e: number): number => e + 1;

  choose(n: number): string {
    switch (n) {
      case 1:
        return 'one';
      default:
        return 'other';
    }
  }
}
