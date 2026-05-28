# sdlc — a closed-loop software-development-lifecycle harness

Takes a GitHub issue to a mergeable PR through a two-agent loop, then folds what was
learned back into a durable per-repo playbook. The **methodology** (skills, the qa
subagent, soft gates, the role contract) lives here and is reused across repos; each
consuming repo owns only its **artifacts** (`PLAYBOOK.md`, auto-memory, a domain brief).

## The two-agent model

| Agent | Role |
|---|---|
| **control** | the long-running outer-loop session (you) — ranks the backlog, dispatches, reviews, merges |
| **asset** | a per-issue inner-loop Claude Code session in a tmux window — researches, plans, builds, opens + iterates one PR; **never merges** |

The asset is a peer agent, not a subagent. Comms are **async over GitHub**: the asset
surfaces decisions (`## Plan`, parked questions) on the issue/PR; control reads them via
`assets-dispatch --check` + the `asset-heartbeat` and un-parks via `--continue`. Both can
spawn a fresh-context reviewer for qa.

### The assets ⟷ sdlc boundary

| | **assets** owns | **sdlc** owns |
|---|---|---|
| | the asset **runtime** (task-agnostic): spawn / `--check` / `--continue` / `--btw` / recall, worktree, monitors (signal / heartbeat / pr-completion), tmux-comms | the **workflow** (this methodology): backlog, the brief, the asset role-contract, review / retro / release / qa |

`sdlc:dispatch` is a thin composer — it builds the prompt and hands off to `assets-dispatch`;
it does NOT re-implement comms or monitors.

## The loop + its vocabulary

```
backlog → dispatch → [asset: plan → build → report] → wrap-up (merge + review + cleanup) → … → retro
```

| Stage | What | By |
|---|---|---|
| **backlog** | rank dispatchable issues (bug > refactor > feature) | control |
| **dispatch** | brief + role-contract + spawn the asset | control |
| **report** | the asset's end-of-PR reflection (went right / wrong / harness gaps / proposed deltas) | asset |
| **wrap-up** | the blessed close-out for a ready PR: gate → merge (policy-respecting) → review → cleanup, as one ritual | control |
| **review** | per-PR: consume the report, apply ledger deltas (folded into `wrap-up`; also runnable standalone) | control |
| **retro** | per-release: synthesize across the whole window for cross-PR patterns | control |
| **optimize** | inner-loop iterative tuning over (perf, cost-time, cost-$) | asset |
| **release** | cut the tag, then run `retro` | control |

## Install

1. Add this marketplace + enable the plugin (and its deps):
   ```jsonc
   // .claude/settings.json
   "enabledPlugins": {
     "sdlc@machine": true,
     "assets@machine": true
   }
   ```
2. (optional) `bash ${CLAUDE_PLUGIN_ROOT}/hooks/install-git-hooks` — wires the SDD/TDD
   soft gates into the repo's `core.hooksPath`. Skip if you don't want them.
3. That's it. The loop runs on **convention** — no config required.

## Convention over configuration

With zero config a repo gets a working loop:

- `PLAYBOOK.md` at the repo root — the durable learning artifact, a **reinforcement ledger
  over memory** (`review`/`retro` increment `reinforced`/`contradicted` counts on memory-backed
  entries, never write prose; created on first use).
- **auto-memory** — `~/.claude/projects/<project-slug>/memory/` (Claude Code derives
  `<project-slug>` from the repo path); `MEMORY.md` is its index.
- `.claude/sdlc/brief.md` — your repo's **domain brief** (how to scope tests/verification
  here, runtime invariants, deploy provenance). Optional; absent → generic briefs.

Write `.claude/sdlc.toml` only to override (frozen paths, release command, prod-gating,
the soft-gate globs). See `config.example.toml`. The `schema_version` field is the
upgrade hinge — artifacts live in the repo, never in the plugin, so a plugin upgrade
(`bump + reinstall`) can't disturb them. When a plugin upgrade bumps the schema, **`UPGRADING.md`**
carries the per-version migration a consuming repo runs on its own artifacts (current: `1 → 2`,
the PLAYBOOK ledger migration).

## Dependencies

- **assets** — the asset runtime: tmux dispatch + lifecycle + the `asset-heartbeat` /
  `pr-completion-monitor` watchers control arms after a dispatch, and the tmux-comms path
  (`--check` / `--continue`). Control↔asset decisions surface async on the GitHub issue/PR —
  there is no separate comms plugin.

## Merge policy

Assets never merge. Control merges on the owner's behalf only for explicitly approved
classes; real-world actions (deploy / arm / posture / promote) stay human-gated when
`prod_gated = true`.

**`/wrap-up` is the blessed merge path.** A ready closed-loop PR is closed via `/wrap-up`
(gate → merge → review → cleanup as one ritual), **not** a raw `gh pr merge` — raw-merging
skips the per-PR review, which is the lossiness `wrap-up` exists to prevent. `wrap-up`
enforces the pre-merge gate (CI green + review body read + qa) and respects `prod_gated`
(it won't merge a gated class; control invoking it is the approval for approved classes).

## Changelog & versioning

Every version bump requires a `CHANGELOG.md` entry. A breaking change additionally requires
an `UPGRADING.md` section (plus a `schema_version` bump for schema-keyed plugins like this one).
Enforced by `tests/test_structure.sh`.
