import { Old } from "./old";
import { New } from "./new";

export const viaInstance = new Old().instanceOnly;
export const made = Old.make(3);
export const existing = new New().existing();
