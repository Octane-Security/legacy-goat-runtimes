# triggers

One runnable proof-of-exploit per vulnerability instance, keyed by its `LG-...` id. Each drives the
running stack to demonstrate the vuln is live. Operator-side only: triggers need the running stack
and are never committed to a blind branch.

Acceptance: every trigger fires on `main` and `vulnerable`; none fires on `fixed`.

Each trigger talks to the service its sink lives in, which is often a module port rather than the
console: see [../docs/attacker-position.md](../docs/attacker-position.md) for the position each one
assumes.
