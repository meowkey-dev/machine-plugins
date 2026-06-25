---
name: optimize
description: Inner-loop GEPA-style iterative optimization. Pareto frontier over (perf, cost-time, cost-$) with LLM reflection on execution traces. Noise-robust (replicate before promoting a noisy metric). Scope is the artifact class the dispatch brief names (e.g. a prompt). Trigger on "optimize the prompt", "run a GEPA pass", or /optimize.
user-invocable: true
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---

# /optimize — GEPA-style inner loop

Inner-loop skill — used by the asset when an issue is an optimization task. Pareto-frontier search over (perf, cost-time, cost-$) with LLM reflection on execution traces.

## Scope

Optimize **only the artifact class the dispatch brief names** (e.g. a prompt template, a config). Anything outside that class — and anything in the repo's `frozen_paths` (`.claude/sdlc.toml`) — is off-limits unless the brief explicitly authorizes it. When in doubt, surface to control rather than widening scope.

## Loop

1. **Select** a candidate from the Pareto frontier over (perf, cost-time, cost-$).
2. **Execute** a minibatch evaluation, capturing traces (per-example outcomes, error patterns).
3. **Reflect**: read traces; diagnose where the artifact fails. Be concrete about which examples broke and why — no hand-waving.
4. **Mutate**: a targeted change, informed by accumulated lessons from earlier failed candidates in this run.
5. **Accept**: if the new candidate is non-dominated on (perf, cost-time, cost-$), add it to the frontier.

## Noise robustness

If the repo's perf metric is noisy (the brief should state the single-run swing, if known), a perf promotion requires a ≥N-replicate mean±band — not a single run. A single-run improvement inside the noise band is **not** promoted. If the brief doesn't quantify noise, measure it (a few replicates of the baseline) before trusting any delta.

## Pareto axes

- **perf**: the repo's quality metric(s), as defined in the domain brief — replicated if noisy
- **cost-time**: wall-clock minutes per evaluation
- **cost-$**: compute / API spend per evaluation

## Output

A markdown summary the asset includes in its iteration comment:

| Candidate | Mutation | Perf | Cost-time | Cost-$ | Dominated by |
|---|---|---|---|---|---|

Plus the current Pareto frontier (frontier candidates only).

The asset decides which (if any) candidate to land. The skill is advisory; the asset commits.
