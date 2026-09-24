import { Greeter } from "./Greeter";

export function run(): string {
  return new Greeter().greet("world");
}
