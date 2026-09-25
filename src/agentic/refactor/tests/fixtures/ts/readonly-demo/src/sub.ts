import { Base } from "./base";

export class Sub extends Base {
  subclassRedeclared: number = 7;

  touch(): void {
    this.subclassWritten = 8;
  }
}
