interface Config {
  first: number;
  second: number;
}

export function describe(config: Config): number {
  const { first, second } = config;
  return first + second;
}
