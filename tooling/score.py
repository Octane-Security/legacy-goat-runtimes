#!/usr/bin/env python3
"""Score a scanner's SARIF against a profile's ground-truth SARIF.

Reachability-aware scoring: a scanner is credited for finding instances that are actually
EXPLOITABLE under the scored profile, and penalized for flagging present-but-unexploitable
instances (hard negatives) as findings, and for findings that match no known instance.

Matching is by location: same file (basename) and overlapping line ranges (with a small window,
since a scanner reports the sink line, which lies inside the instance's annotated range).

Metrics (per profile):
  detection_recall        detected_exploitable / total_exploitable
  exploitability_precision detected_exploitable / (detected_exploitable + flagged_hard_negatives)
  hard_negative_flags     exploitable-instances a good reachability engine should NOT report
  false_positives         scanner findings matching no instance at all

usage: score.py <ground-truth.sarif> <scanner.sarif> [--window N] [--json]
"""
import json
import os
import sys

WINDOW = 5


def load_results(path):
    doc = json.load(open(path))
    out = []
    for run in doc.get("runs", []):
        for r in run.get("results", []):
            locs = r.get("locations", [])
            uri, s, e = "", 0, 0
            if locs:
                pl = locs[0].get("physicalLocation", {})
                uri = pl.get("artifactLocation", {}).get("uri", "")
                reg = pl.get("region", {})
                s = int(reg.get("startLine", 0) or 0)
                e = int(reg.get("endLine", s) or s)
            out.append({"raw": r, "uri": uri, "start": s, "end": e,
                        "props": r.get("properties", {}) or {}, "ruleId": r.get("ruleId", "")})
    return out


def base(uri):
    return os.path.basename(uri or "")


def overlaps(gt, f, window):
    if base(gt["uri"]) != base(f["uri"]):
        return False
    if not f["start"]:
        return base(gt["uri"]) == base(f["uri"])  # file-only finding
    return f["start"] <= gt["end"] + window and f["end"] >= gt["start"] - window


def score(gt_path, scanner_path, window=WINDOW):
    gt = load_results(gt_path)
    findings = load_results(scanner_path)

    exploitable = [g for g in gt if g["props"].get("exploitable")]
    hard_neg = [g for g in gt if not g["props"].get("exploitable")]  # unexploitable + present

    matched_findings = set()
    detected_exploitable, missed = [], []
    for g in exploitable:
        hit = None
        for i, f in enumerate(findings):
            if overlaps(g, f, window):
                hit = i
                break
        if hit is not None:
            matched_findings.add(hit)
            detected_exploitable.append(g["props"].get("id"))
        else:
            missed.append(g["props"].get("id"))

    flagged_hard_neg = []
    for g in hard_neg:
        for i, f in enumerate(findings):
            if overlaps(g, f, window):
                matched_findings.add(i)
                flagged_hard_neg.append(g["props"].get("id"))
                break

    false_positives = [f["uri"] + f":" + str(f["start"]) for i, f in enumerate(findings)
                       if i not in matched_findings]

    n_exp = len(exploitable)
    n_det = len(detected_exploitable)
    n_hn = len(flagged_hard_neg)
    recall = n_det / n_exp if n_exp else 1.0
    exp_prec = n_det / (n_det + n_hn) if (n_det + n_hn) else 1.0
    return {
        "total_exploitable": n_exp,
        "detected_exploitable": n_det,
        "missed_exploitable": missed,
        "detection_recall": round(recall, 4),
        "hard_negative_flags": flagged_hard_neg,
        "exploitability_precision": round(exp_prec, 4),
        "false_positives": len(false_positives),
        "false_positive_locations": false_positives,
        "detected_ids": detected_exploitable,
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    window = WINDOW
    if "--window" in sys.argv:
        window = int(sys.argv[sys.argv.index("--window") + 1])
        args = [a for a in args if a != str(window)]
    if len(args) != 2:
        print("usage: score.py <ground-truth.sarif> <scanner.sarif> [--window N] [--json]", file=sys.stderr)
        return 2
    res = score(args[0], args[1], window)
    if as_json:
        print(json.dumps(res, indent=2))
        return 0
    print(f"detection recall         {res['detection_recall']:.0%}  "
          f"({res['detected_exploitable']}/{res['total_exploitable']} exploitable found)")
    print(f"exploitability precision {res['exploitability_precision']:.0%}  "
          f"({res['hard_negative_flags'] and len(res['hard_negative_flags']) or 0} hard-negative(s) flagged)")
    print(f"false positives          {res['false_positives']}")
    if res["missed_exploitable"]:
        print("  missed:   " + ", ".join(res["missed_exploitable"]))
    if res["hard_negative_flags"]:
        print("  hard-neg: " + ", ".join(res["hard_negative_flags"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
