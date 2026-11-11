<!--
Thanks for contributing. Fill in every section; delete the checklists that don't apply to your type
of change. A checked box needs its evidence below it: the command, the commits of both repositories,
and the summary lines of its output. See the Contributing section of the README.
-->

## Linked issue

Closes #

## Companion pull request in legacy-goat

<!-- Link it, or say why none is needed. A regression test for an application fix goes with the fix there. -->

## Type of change

- [ ] Regression test for an application fix
- [ ] Exploit proof (trigger) change
- [ ] Runtime image, adapter, gateway or database change
- [ ] Tooling or documentation

## What changed and why

## Evidence

<!-- For each check below: the command, the commits of both repositories (and the generated tree you deployed), and the summary lines of the output. -->

```text

```

## Every pull request

- [ ] It links an issue (trivial fixes such as typos excepted).
- [ ] `make verify APP_PROFILE=baseline` and `make verify APP_PROFILE=permissive` pass against the `vulnerable` and `fixed` trees of the legacy-goat commit named above (`APP_SRC` set to each generated tree): triggers fire exactly where the answer key grades their instance exploitable on `vulnerable`, and stay inert on `fixed`.
- [ ] `make test`, `make integration` and `make operations` pass against the stack under each profile.
- [ ] Documentation changes with behavior: the README, `docs/attacker-position.md` or `docs/exercising-the-app.md`.
- [ ] Vendored code keeps its license notice.
- [ ] I offer this contribution under the GNU GPL, version 3. It contains no secrets or personal data.

## Regression test for an application fix

- [ ] The test fails against current legacy-goat `main` and passes against the companion pull request's branch (show both runs).
- [ ] The test sends legitimate or malformed input and checks the documented behavior. It is not an exploit chain.

## Exploit proof (trigger) change

- [ ] The trigger keeps the fire and inert verdicts the answer key grades, under both profiles and on both trees.
- [ ] If the change strengthens a guard check, the guard-strength variants still stay inert on `fixed` and under the profile where the instance is unexploitable.
