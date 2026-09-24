import New from "./default";
import { Old } from "./old";

export const a = Old.make(11);
export const tag = new New().tag();
