#!/usr/bin/env python3
"""Generate benchmark/ground-truth.<profile>.sarif from benchmark/manifest.yaml.

One SARIF 2.1.0 file per profile. Each manifest instance becomes one result, located at its
`locations.main` file/line range, tagged with the per-profile ground truth in `properties`:

  - status:      exploitable | unexploitable | present   (this profile's grade)
  - exploitable: bool                                     (status == exploitable)
  - detectable:  bool                                     (the pattern is present in source at all;
                                                            true for every instance incl. hard negatives)
  - cwe, class, id, module, language, gate

`level` is "error" for an exploitable instance under this profile, else "note" -- a scanner that only
reports what it considers exploitable should match the errors; the notes are the hard negatives
(present-but-unexploitable) it should NOT flag as exploitable.

Generated files are never hand-edited; regenerate whenever manifest.yaml changes.
Run via: uv run --with pyyaml python3 gen_ground_truth.py <manifest.yaml> <out_dir>
"""
import json
import os
import sys

import yaml

SCHEMA = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"


def parse_lines(spec):
    """'83-99' -> (83, 99); '44' -> (44, 44); missing -> (1, 1)."""
    if not spec:
        return 1, 1
    s = str(spec)
    if "-" in s:
        a, b = s.split("-", 1)
        return int(a), int(b)
    return int(s), int(s)


def profiles_in(doc):
    seen = []
    for e in doc.get("entries", []):
        for p in (e.get("exploitability", {}) or {}):
            if p not in seen:
                seen.append(p)
    return seen


def rules_for(doc):
    rules, seen = [], set()
    for e in doc.get("entries", []):
        cls = e.get("class", "unknown")
        if cls in seen:
            continue
        seen.add(cls)
        rules.append({
            "id": cls,
            "name": cls,
            "properties": {"cwe": e.get("cwe")},
        })
    return rules


def result_for(entry, profile):
    grade = (entry.get("exploitability", {}) or {}).get(profile) or {}
    status = grade.get("status", "unexploitable") if isinstance(grade, dict) else "unexploitable"
    exploitable = status == "exploitable"
    loc = (entry.get("locations", {}) or {}).get("main", {}) or {}
    start, end = parse_lines(loc.get("lines"))
    gate = grade.get("gate") if isinstance(grade, dict) else None
    return {
        "ruleId": entry.get("class", "unknown"),
        "level": "error" if exploitable else "note",
        "message": {"text": f"{entry.get('id')}: {entry.get('title','')}"},
        "locations": [{
            "physicalLocation": {
                "artifactLocation": {"uri": loc.get("file", "")},
                "region": {"startLine": start, "endLine": end},
            }
        }],
        "properties": {
            "id": entry.get("id"),
            "cwe": entry.get("cwe"),
            "class": entry.get("class"),
            "module": entry.get("module"),
            "language": entry.get("language"),
            "status": status,
            "exploitable": exploitable,
            "detectable": True,
            "gate": gate,
        },
    }


def sarif_for(doc, profile):
    return {
        "$schema": SCHEMA,
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {
                "name": "legacy-goat-ground-truth",
                "informationUri": "https://github.com/legacy-goat",
                "version": str(doc.get("schema_version", 1)),
                "properties": {"profile": profile},
                "rules": rules_for(doc),
            }},
            "results": [result_for(e, profile) for e in doc.get("entries", [])],
        }],
    }


def main():
    if len(sys.argv) != 3:
        print("usage: gen_ground_truth.py <manifest.yaml> <out_dir>", file=sys.stderr)
        return 2
    manifest, out_dir = sys.argv[1], sys.argv[2]
    doc = yaml.safe_load(open(manifest)) or {}
    profiles = profiles_in(doc)
    if not profiles:
        print("no profiles found in manifest exploitability grades", file=sys.stderr)
        return 1
    os.makedirs(out_dir, exist_ok=True)
    for p in profiles:
        path = os.path.join(out_dir, f"ground-truth.{p}.sarif")
        with open(path, "w") as f:
            json.dump(sarif_for(doc, p), f, indent=2)
            f.write("\n")
        n = len(doc.get("entries", []))
        ex = sum(1 for e in doc["entries"]
                 if ((e.get("exploitability", {}) or {}).get(p) or {}).get("status") == "exploitable")
        print(f"wrote {path}  ({n} instances, {ex} exploitable under {p})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
