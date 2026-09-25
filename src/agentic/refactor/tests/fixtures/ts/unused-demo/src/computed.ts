function key(): string {
  return "k";
}

export function built(): number {
  const computed = { [key()]: 1 };
  const plain = { value: 1 };

  return 0;
}
