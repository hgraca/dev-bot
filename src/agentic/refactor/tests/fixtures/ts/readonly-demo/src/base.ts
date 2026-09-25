export class Base {
  ctorOnly: number;
  methodWritten: number;
  initialised = 5;
  readonly already = 6;
  nested: number;
  subclassWritten: number;
  subclassRedeclared: number;

  constructor(public promoted = 0) {
    this.ctorOnly = 1;
    this.methodWritten = 2;
    this.nested = 3;
    this.subclassWritten = 4;
    this.subclassRedeclared = 5;
    setTimeout(() => {
      this.nested = 6;
    });
  }

  bump(): void {
    this.methodWritten = 9;
  }
}
