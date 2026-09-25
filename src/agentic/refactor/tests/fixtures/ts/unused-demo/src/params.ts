export function clean(first: string, spare: string): string {
  return first;
}

export const oneArgument = clean("x");

export function passed(first: string, punctuation: string): string {
  return first;
}

export const withPunctuation = passed("hi", "!");

export function overloaded(value: string, flag?: boolean): string;
export function overloaded(value: number, flag?: boolean): string;
export function overloaded(value: string | number, flag?: boolean): string {
  return String(value);
}

export const oneOverloadArgument = overloaded("x");

export function underscore(first: string, _second: string): string {
  return first;
}

export const underscored = underscore("a");

function asValue(solo: string): string {
  return "value";
}

export const referenced = asValue;
