export class Params {
  constructor(public seed: number) {}

  read(): number {
    return this.seed;
  }
}
