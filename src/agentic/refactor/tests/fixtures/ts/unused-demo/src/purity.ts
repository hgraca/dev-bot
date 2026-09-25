function sideEffect(): number {
  return 1;
}

export function purity(): number {
  const array = [sideEffect()];
  const object = { value: sideEffect() };
  const plainArray = [1, 2];
  const plainObject = { value: 1 };

  return 0;
}
