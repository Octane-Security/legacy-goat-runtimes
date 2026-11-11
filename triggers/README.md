# triggers

One runnable proof-of-exploit per vulnerability instance, keyed by its `LG-...` id: `<id>.py` defines
`fire()`, which drives the running stack and returns whether the flaw is live and what the stack
answered. Operator-side only: triggers need the running stack and are never committed to a blind
branch.

Acceptance: every trigger fires on `main` and `vulnerable` where the answer key grades its instance
exploitable; none fires on `fixed`.

```
./run_trigger.sh LG-AC-001   # exit 0 fired, 1 not fired, 2 could not run
./run_trigger.sh --all       # FIRED or inert per trigger; exit 0 only if none fired (make triggers)
./run_trigger.sh --list
```

`make verify` runs every trigger against the answer key's grades for the profile
(`../test/test_exploitability.py`).

Each trigger talks to the service its sink lives in, which is often a module port rather than the
console: see [../docs/attacker-position.md](../docs/attacker-position.md) for the position each one
assumes. A new trigger follows the same shape: a docstring that says what it sends, when it fires and
why the fix makes it inert, the environment it reads, and a `fire()` that returns `(fired, detail)`.
