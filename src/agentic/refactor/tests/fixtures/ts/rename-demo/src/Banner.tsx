/**
 * A reference held in JSX text — literal, like a string, so the type-aware
 * rename cannot see it either.
 */
export function Banner() {
  return <h1>greet</h1>;
}
