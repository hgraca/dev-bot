import { Base } from "./base";

const b = new Base();

export const exposed = b.usedBySubclass() + b.overriddenBySubclass();
