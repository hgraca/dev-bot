export const viaArrow = (first: number, unused?: number): number => first;

export const called = viaArrow(1);

export const viaExpression = function (first: number, spare: number): number {
  return first;
};
