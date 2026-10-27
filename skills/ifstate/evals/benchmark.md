# Skill verification benchmark

Three realistic prompts were run with the skill and without it in the same turn. Independent graders checked the assertions in `evals.json` against the answers and primary sources.

| Configuration | Mean per-eval pass rate | Mean wall time |
|---|---:|---:|
| With skill | 100% | 137.4 s |
| Without skill | 63.3% | 646.1 s |

Per-eval results:

- Router/LACP/WireGuard: 5/5 with skill, 4/5 without. The baseline inherited the 2.4.2 `postPatch` paths and its 2.5.1 package would fail during patching.
- FRR/EVPN/Cilium: 5/5 with skill, 3/5 without. The baseline proposed flood-and-learn/static FDB behavior inappropriate for FRR-owned EVPN and did not address the SVD limitation correctly.
- Oneshot/VM/version debugging: 4/4 with skill, 2/4 without. The baseline misdiagnosed the genuine 2.5.1 version-string wart and expected an unreachable `--version` result.

Basic oneshot, orphan-cleanup, and protocol-196 assertions passed in both configurations and are necessary but non-discriminating coverage. The release-specific package, version, EVPN FDB, and SVD assertions demonstrate the skill's value.

The harness did not report actual token counts, so timing and assertion pass rates are the meaningful metrics. The review viewer was generated with the skill-creator `generate_review.py` script; the temporary run outputs are not part of the skill.
