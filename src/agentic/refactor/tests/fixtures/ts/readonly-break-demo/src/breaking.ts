export class Breaking {
  element = 0;
  deleted?: number;
  static carried = 0;

  constructor() {
    Breaking.carried++;
  }

  touch(): void {
    this["element"] = 2;
    delete this.deleted;
  }
}
