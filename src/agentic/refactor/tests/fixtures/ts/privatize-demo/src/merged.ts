export class Merged {
  describe(): string {
    return "merged";
  }

  read(): string {
    return this.describe();
  }
}

export interface Merged {
  describe(): string;
}
