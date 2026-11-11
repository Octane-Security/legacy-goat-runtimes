"""Load and run the exploit proofs in triggers/.

Each proof is `triggers/<id>.py`, named after its manifest entry, and defines `fire()`. `fire()`
drives the running stack and returns `(fired, detail)`: `fired` is true when the flaw is live, and
`detail` says what the stack answered. An exception means the proof could not run.

Command line (triggers/run_trigger.sh wraps it):

    python -m harness.triggers LG-AC-001     # exit 0 fired, 1 not fired, 2 could not run
    python -m harness.triggers --all         # one line per proof; exit 0 only if none fired
    python -m harness.triggers --list
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
import traceback
from pathlib import Path
from types import ModuleType

from harness import env

TRIGGERS_DIR = env.ROOT / "triggers"


def path(instance: str) -> Path:
    return TRIGGERS_DIR / f"{instance}.py"


def available() -> list[str]:
    return sorted(p.stem for p in TRIGGERS_DIR.glob("LG-*.py"))


def load(instance: str) -> ModuleType:
    source = path(instance)
    if not source.is_file():
        raise FileNotFoundError(f"no trigger at {source}")
    spec = importlib.util.spec_from_file_location(f"trigger_{instance.replace('-', '_')}", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not callable(getattr(module, "fire", None)):
        raise AttributeError(f"{source} defines no fire()")
    return module


def run(instance: str) -> tuple[bool, str]:
    fired, detail = load(instance).fire()
    return bool(fired), str(detail)


def _run_one(instance: str) -> int:
    try:
        fired, detail = run(instance)
    except Exception:
        traceback.print_exc()
        print(f"{instance} could not run", file=sys.stderr)
        return 2
    if fired:
        print(f"{instance} FIRED: {detail}")
        return 0
    print(f"{instance} not fired: {detail}", file=sys.stderr)
    return 1


def _run_all() -> int:
    status = 0
    for instance in available():
        try:
            fired, _ = run(instance)
        except Exception as error:
            print(f"ERROR  {instance}: {error!r}")
            status = 1
            continue
        print(f"{'FIRED' if fired else 'inert'}  {instance}")
        if fired:
            status = 1
    return status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="run_trigger.sh",
        description="Run an exploit proof against the running stack.",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("instance", nargs="?", help="the proof to run, by manifest id (LG-...)")
    group.add_argument("--all", action="store_true", help="run every proof; exit 0 only if none fired")
    group.add_argument("--list", action="store_true", help="list the proofs")
    args = parser.parse_args(argv)
    if args.list:
        print("\n".join(available()))
        return 0
    if args.all:
        return _run_all()
    return _run_one(args.instance)


if __name__ == "__main__":
    sys.exit(main())
