#!/usr/bin/env python3
"""Check that every ground-truth region still points at its construct in a given app tree.

gen_ground_truth.py copies each manifest entry's `locations.main` range into the SARIF unchanged.
That range is only right while the tree being scored has the same lines as main's app source, which
is the case for the blind `vulnerable` tree: the generator copies main's app files byte for byte.
This check proves it per profile, for main or for any generated tree:

  - each SARIF result's file exists in the tree and its region fits inside the file;
  - the region equals the manifest's `locations.main` range for that instance;
  - the manifest `anchor` (a code fragment) appears within the region's lines;
  - every other named location in the manifest (e.g. LG-AUTH-001 `resolver`) holds too.

usage: check_alignment.py <benchmark_dir> <tree_dir>
Run via: uv run --with pyyaml python3 check_alignment.py ...   exit 0 = aligned
"""
import glob
import json
import os
import sys

import yaml


def parse_lines(spec):
    a, _, b = str(spec).partition("-")
    return int(a), int(b or a)


def check_loc(tree, loc):
    """Return None when loc's anchor sits inside its lines in tree, else the problem."""
    path = os.path.join(tree, loc["file"])
    if not os.path.isfile(path):
        return f"{loc['file']} missing"
    lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
    a, b = parse_lines(loc["lines"])
    if b > len(lines):
        return f"{loc['file']}:{a}-{b} past end of file ({len(lines)} lines)"
    anchor = loc.get("anchor")
    if not anchor:
        return f"{loc['file']}:{a}-{b} has no anchor in the manifest"
    if not any(anchor in ln for ln in lines[a - 1:b]):
        found = [i + 1 for i, ln in enumerate(lines) if anchor in ln]
        return f"{loc['file']}:{a}-{b} lacks anchor {anchor!r} (found at {found or 'nowhere'})"
    return None


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().split("\n\n")[-1], file=sys.stderr)
        return 2
    bench, tree = argv[1], argv[2]
    doc = yaml.safe_load(open(os.path.join(bench, "manifest.yaml"))) or {}
    entries = {e["id"]: e for e in doc.get("entries", [])}
    sarifs = sorted(glob.glob(os.path.join(bench, "ground-truth.*.sarif")))
    if not sarifs:
        print(f"no ground-truth.*.sarif under {bench}", file=sys.stderr)
        return 1
    failures = 0
    for sp in sarifs:
        profile = os.path.basename(sp)[len("ground-truth."):-len(".sarif")]
        results = json.load(open(sp))["runs"][0]["results"]
        bad = []
        for r in results:
            iid = r["properties"]["id"]
            phys = r["locations"][0]["physicalLocation"]
            region = phys["region"]
            e = entries.get(iid)
            if e is None:
                bad.append(f"{iid}: not in the manifest")
                continue
            loc = e["locations"]["main"]
            if (phys["artifactLocation"]["uri"], (region["startLine"], region["endLine"])) != (
                    loc["file"], parse_lines(loc["lines"])):
                bad.append(f"{iid}: SARIF region differs from the manifest (regenerate ground truth)")
            problem = check_loc(tree, loc)
            if problem:
                bad.append(f"{iid}: {problem}")
        status = "aligned" if not bad else f"{len(bad)} MISALIGNED"
        print(f"[{profile}] {len(results)} results vs {tree}: {status}")
        for b in bad:
            print(f"    {b}")
        failures += len(bad)
    extra = []
    for iid, e in entries.items():
        for name, loc in e["locations"].items():
            if name != "main":
                problem = check_loc(tree, loc)
                if problem:
                    extra.append(f"{iid} {name}: {problem}")
    print(f"[extra locations] {'aligned' if not extra else f'{len(extra)} MISALIGNED'}")
    for b in extra:
        print(f"    {b}")
    failures += len(extra)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
