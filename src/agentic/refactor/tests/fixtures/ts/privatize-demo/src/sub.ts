import { Base } from "./base";

export class Sub extends Base {
  override overriddenBySubclass(): number {
    return 60;
  }

  touch(): number {
    return this.usedBySubclass();
  }
}
