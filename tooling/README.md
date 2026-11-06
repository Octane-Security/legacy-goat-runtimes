# tooling — scoring

Operator-side scripts that score a scanner against the benchmark's ground truth. Blind-branch
generation and its gates live in the legacy-goat repo's own `tooling/`, so its CI can push the
branches with `GITHUB_TOKEN` and no cross-repo secret.

- **ground-truth generation** (`gen_ground_truth.py`, `gen-ground-truth.sh`) — regenerate
  `benchmark/ground-truth.<profile>.sarif` (one per profile) from `benchmark/manifest.yaml`. Each
  instance becomes one SARIF result at its `locations.main` range, tagged in `properties` with the
  per-profile grade (`status`, `exploitable`, `cwe`, `class`, `gate`); `level` is `error` for an
  exploitable instance, `note` for a hard negative. `make ground-truth`. Never hand-edit the output.
  The ranges are copied as written: they hold for the blind `vulnerable` tree because its app files
  are main's byte for byte.
- **alignment check** (`check_alignment.py`) — prove every SARIF region still holds its construct:
  the region matches the manifest and contains the entry's `anchor` in a given tree, per profile.
  `make check-alignment` (main) or `make check-alignment TREE=<generated vulnerable tree>`.
- **scoring** (`score.py`) — diff a scanner's SARIF against a profile's ground truth by location
  (basename + overlapping line range, small window). Reports detection recall over exploitable
  instances, exploitability precision (penalizing flagged hard negatives), and pure false positives.
  `make score SCANNER=out.sarif APP_PROFILE=permissive`. Flipping the profile re-scores the SAME
  findings against that profile's grades — the reachability discrimination the benchmark measures.
