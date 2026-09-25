export class Overloaded {
  format(value: string): string;
  format(value: number): string;
  format(value: string | number): string {
    return String(value);
  }

  read(): string {
    return this.format(1);
  }
}
