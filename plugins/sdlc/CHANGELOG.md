# Changelog

All notable changes to the sdlc plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.5.3] - 2026-05-26
### Documentation
- OSS-readiness redaction: genericized the `UPGRADING.md` worked-reference (dropped a private downstream repo + PR pointer) and replaced the private domain terms in `tests/test_structure.sh`'s leak-guard with neutral placeholders (the guard still runs; forks extend `DOWNSTREAM_TERMS`). No behavior change.

## [0.5.2] - 2026-05-24
### Added
- CHANGELOG.md (this file); version-bump convention note in README.

## [0.5.1] - 2026-05-24
### Changed
- Codified A/B/C ledger-eligibility scope in `review`, `retro`, and `wrap-up`: only A (closed-loop methodology) and B (reusable techniques) earn ledger rows; C (static domain facts) stays memory-only.

## [0.5.0] - 2026-05-24
### Changed
- `review` and `retro` now include an explicit contradiction-hunt pass; a null result must be stated, not skipped — fixes the up-only ledger ratchet.
- Added shell `read`/`$IFS` discipline guidance to the dispatch brief boilerplate and the `qa.md` rubric.

## [0.4.0] - 2026-05-24
### Added
- `/wrap-up` skill — the blessed post-PR close-out ritual (gate → merge → review → cleanup as one bound operation). Replaces raw `gh pr merge` + deferred review.

## [0.3.0] - 2026-05-24
### Changed
- `review` and `retro` now maintain PLAYBOOK as a reinforcement ledger over memory: increment `reinforced`/`contradicted` counts on memory-backed entries, never write prose. `schema_version` bumped 1 → 2.
### Added
- `UPGRADING.md` with the schema_version 1 → 2 migration guide.

## [0.2.1] - 2026-05-23
### Changed
- Hardened `dispatch` brief: added four-surface private-git-dep adoption checklist (CI, build backend, deploy target, asset worktree).

## [0.2.0] - 2026-05-23
### Changed
- Clarified assets ↔ sdlc responsibility boundary: `dispatch` is a thin composer that builds the prompt and hands off to `assets-dispatch`; it does not re-implement comms or monitors.
- Dropped `mesh-channel` as a loop dependency; control ↔ asset comms are async over the GitHub issue/PR.

## [0.1.0] - 2026-05-23
### Added
- Initial plugin: `backlog`, `dispatch`, `review`, `retro`, `release`, `optimize` skills; `qa` subagent; `pre-commit` (SDD) and `pre-push` (TDD) soft-gate hooks.
