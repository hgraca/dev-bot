export class Base {
  internalOnly(): number {
    this.accessor = 1;
    return this.helper() + this.value;
  }

  helper(): number {
    return 1;
  }

  value = 2;

  unusedHere(): number {
    return 3;
  }

  private alreadyPrivate(): number {
    return 4;
  }

  usedBySubclass(): number {
    return 5;
  }

  overriddenBySubclass(): number {
    return 6;
  }

  get accessor(): number {
    return this.value;
  }

  set accessor(v: number) {
    this.value = v;
  }
}
