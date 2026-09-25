export function compute(): number {
  const used = 2;
  const removed = 1;
  const dead = 3,
    live = 4;
  const effects = sideEffect();
  const _ignored = 5;

  return used + live;
}

export function total(values: number[]): number {
  let sum = 0;
  for (const entry of values) {
    sum += 1;
  }
  return sum;
}

function sideEffect(): number {
  return 0;
}
