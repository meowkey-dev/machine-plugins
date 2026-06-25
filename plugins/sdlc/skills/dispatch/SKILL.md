---
name: dispatch
description: Dispatch a long-lived asset (single Claude Code session in a tmux window) to take a single GitHub issue end-to-end. Composes the brief + role-contract, invokes assets-dispatch, arms the heartbeat + PR-completion monitors. Trigger on "dispatch issue #N", "spawn asset for #N", or /dispatch <N>.
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - Skill
---

# /dispatch <issue#> — launch an asset for one issue

Outer-loop skill. Sends one issue's worth of work to a single Claude Code session running in a tmux window (the **asset**, our inner-loop agent). The asset opens + iterates a PR; it never merges. Control (or owner) merges.

## Two-agent model

| Agent | Identity | Session |
|---|---|---|
| **control** | the long-running CC session that invokes this skill (the outer loop — you) | yours |
| **asset** | the inner-loop CC session that does the work for ONE issue | new tmux window |

The asset is NOT a subagent — it's a full CC session with its own context, tools, and runtime. It can spawn subagents (e.g. a fresh-context reviewer) for isolated reads.

**Comms = GitHub (async).** There is no parallel message store. The asset surfaces decisions — `## Plan`, parked questions — as comments on the **GitHub issue/PR**; control reads them via `assets-dispatch --check` + the `asset-heartbeat` (which catches a silently-parked asset) and un-parks via `assets-dispatch --continue` (the reliable tmux nudge). The signal-file `.done` is the async lifecycle wake.

## Boundary (assets ⟷ sdlc)

`sdlc:dispatch` is a **thin composer**: build the prompt (brief + role-contract) → hand it to `assets-dispatch` → kick off the rituals. It must NOT re-implement comms or monitors.

| | **assets** owns | **sdlc** owns |
|---|---|---|
| | the asset **runtime** (task-agnostic): spawn / `--check` / `--continue` / `--btw` / recall, worktree, monitors (signal / heartbeat / pr-completion), tmux-comms | the **workflow** (closed-loop methodology): backlog, the brief (domain rubric + verification scoping), the asset role-contract (plan-before-build / report / qa / escalation), review / retro / release |

Paths below: `<signals>` = the `assets` plugin's `paths.signals`; `<repo>` = a short slug for this repo; `<frozen_paths>` / `<brief>` from `.claude/sdlc.toml` (defaults: none / `.claude/sdlc/brief.md`).

## Procedure

### 1. Read the issue + draft brief

`gh issue view <N> --comments --json title,body,labels,comments`

If `/backlog` persisted a digest at `/tmp/sdlc-backlog-<N>.md` (or `/tmp/sdlc-backlog-summary.md`) and it's fresh, reuse it. Otherwise draft one. The brief MUST include:

- One-paragraph problem statement
- Suggested first cut (optional but recommended for thin issues)
- **SDD touchpoint**: which runtime-contract doc section (if the repo keeps one, e.g. `SPEC.md`), or `NONE`
- **TDD plan**: which tests
- **Verification plan, scoped by change-class.** Match verification effort to blast radius — don't run a heavy end-to-end suite when a local check carries the evidence, and don't lean on a unit test when the change crosses layers. The repo's domain brief (`<brief>`) should enumerate the repo-specific change-classes + their verification methods; pull from it. If `<brief>` is absent, use the litmus: *does the heavy check tell me anything the cheap per-unit check + a hand-verified example wouldn't?* No → don't specify it.
- **Cost budget**: `<min>min wall-clock / $<dollars> marginal` — say "marginal" explicitly (self-hosted compute is `$0 marginal`; bare "$0" reads as "can't run it").
- **Runtime setup the asset needs** (from `<brief>` when applicable): DB/env vars, service endpoints, tunnels, fixtures. Name them concretely — don't say "the server."
- **CI default — required-check vs `paths-ignore`.** If the brief touches CI workflows: a workflow destined to become a **required status check MUST NOT use `paths-ignore`** (or must add a skip-reports-success job). A PR that skips a `paths-ignore`'d required check leaves it unreported → merge deadlocks forever. (Non-required workflows may keep `paths-ignore` safely.)
- **Verbatim-lift checklist (lift / extraction / SPEC-class tasks only).** When the task moves code verbatim or makes record-shape claims, inline this hard pre-commit checklist into the brief — it's repeatedly violated when left as soft guidance:
  - (a) literal `diff` each moved function against its source — don't eyeball it.
  - (b) derive every time/epoch fixture **via the code**, never by hand.
  - (c) trace **all** branches, including conditional keys, for any record-shape claim.
- **Shell field-emit / `$IFS` discipline (shell / lift-class tasks that emit `read`-parsed fields).** When a script emits structured fields parsed by `read`, pick a delimiter that *cannot appear in the values* and scope `IFS` to it (`IFS=$'\t' read …`) — the default `$IFS` (space + tab + newline) word-splits any value containing a space. Require a fixture whose value contains the OTHER common separators: spaces in CI check-names (e.g. `build / lint`), slashes/commas in paths/labels. Space-free fixtures passing the local suite is not evidence — that's exactly the blind spot that ships the bug.
- **Private git-dependency adoption checklist (tasks that add a new private git dep only).** A private git dep needs the credential wired on **every surface that clones it**; each surface fails *separately* and *late*, so enumerate all four in the brief up front (turns N stop-and-debug rounds into 0):
  - (a) **CI** — add `git config url."https://x-access-token:${ORG_READ_TOKEN}@github.com/<org>/".insteadOf "https://github.com/<org>/"` (org-level Actions secret) as a step **before** `uv sync`. (This is the credential gotcha; the *separate* CI gotcha is the required-check vs `paths-ignore` note above — both bite CI, keep them distinct.)
  - (b) **Build backend** — set `allow-direct-references = true` (hatchling rejects direct git refs otherwise).
  - (c) **Deploy / prod target** — git credential store or deploy key with org read; the deploy `uv sync` clones it too. **Verify in the service/systemd env, not just an interactive shell** — `HOME`/`PATH` can differ, so an interactive success doesn't prove the service can clone.
  - (d) **Asset worktree** — `uv sync` in the fresh worktree before handoff. The `assets` plugin already does this when a lockfile is present (machine#129) — don't re-specify it, just confirm the worktree is uv-synced.

### 2. Owner sign-off

Show the brief to the user; wait for explicit OK. Do not dispatch without it.

### 3. Compose the dispatch prompt file

Write `<signals>/issue-<N>.prompt` with: the role-contract boilerplate below + the issue link + the brief + the signal-file completion path (`<signals>/issue-<N>.done`).

**Append the qa rubric.** `qa` is not a registered subagent type in asset worktrees (see step 5), so the asset can't load it at runtime — control must inline it. After the role-contract block, append a `## QA rubric (embed verbatim when spawning the reviewer)` heading followed by the full contents of `${CLAUDE_PLUGIN_ROOT}/agents/qa.md` (resolvable at compose time via the plugin-root path the harness exposes). The asset then spawns its reviewer with this text — it never looks up a file path of its own.

> You are the **inner-loop asset** for this repo's closed loop. You own one workstream: issue #N.
>
> **Comms = GitHub (async).** Surface decisions and parked questions as comments — there is no separate message channel. **Comment-placement contract:** your `## Plan`, `## Iteration N`, and `## Report` go on the **PR** (the `## Plan` goes on the **issue** if the PR isn't open yet); control's review goes on the **issue**. When you park, STOP — control reads your comment via `--check`/the heartbeat and un-parks you with a `--continue` nudge.
>
> **Procedure:**
> 1. Research the issue + repo at HEAD. If the brief contradicts the repo, **surface it on the issue and STOP (parked)** — don't force.
> 2. Plan: post a `## Plan` comment on the issue with SDD / TDD / verification / cost specifics AND an **Open questions** subsection for anything you can't resolve from the brief alone. STOP (parked) and wait for control's OK on the issue.
>    **Tag each Open Question** `[DECIDE-before-build]` (cross-cutting design axis — control + owner MUST answer before you leave Plan) or `[FYI/default-ok]` (mechanical / safety / naming — control may accept your default). When in doubt, mark `[DECIDE-before-build]` — the tag forces the real choices to surface instead of being batch-approved.
> 3. Build on a feature branch; open a PR; iterate. **Do at least one real end-to-end smoke** (real DB / endpoint / dev environment) if the artifact integrates with running infra — mocks miss silent filters *between* layers. **Any real-world / production action is human-gated** — surface on the PR and STOP before invoking; never auto-deploy or act on production yourself.
> 4. Iteration comments (`## Iteration N` / Problem / Work / Outcome (perf + cost) / Session path) go **on the PR**.
> 5. After every code-complete iteration, spawn a fresh-context reviewer (via the Agent tool) for PR review. **Note:** `qa` is NOT a registered subagent type in asset worktrees — spawn `general-purpose` and embed the **QA rubric appended below this role-contract** verbatim into the reviewer's prompt. Do NOT look up a rubric file path at runtime; control already inlined it. Address findings.
> 6. **Escalation rule.** If the reviewer returns:
>    - `addresses-issue: PARTIAL` or `DRIFTED` → **always surface on the issue and STOP** (scope decision, not fix-in-place).
>    - `test coverage: INSUFFICIENT` → iterate IN-PLACE (add the tests, re-run the reviewer). Escalate only on REPEAT INSUFFICIENT on the same axis.
>    - Any other decision you can't make from the brief alone → surface and STOP (parked).
>    - Cost-budget would be exceeded → stop, surface on the issue.
> 7. **Before declaring done, post a `## Report` section on the PR** with:
>    ```
>    ## Report
>    **Went right:** <2-3 concrete bullets>
>    **Went wrong:** <2-3 concrete bullets>
>    **Harness gaps:** <misfires in the brief / role contract / qa>
>    **Proposed playbook deltas:** <memory / playbook / skill edits worth doing>
>    ```
> 8. **Before writing `.done`, re-read the issue + PR one final time** — if a control comment arrived since your last read, treat it as a new iteration; do NOT write `.done` yet.
> 9. Write the completion signal: `<signals>/issue-<N>.done` with one line — `PR #<m> ready for merge` or `parked: <reason>`.
>
> **Hard constraints:**
> - Never merge; never push to main; never `--no-verify`.
> - **Prefer `git add <explicit paths>` over `git add -A`** — the worktree is shared with subagents; `-A` can sweep up their scratch. If you must use `-A`, audit the staged diff first.
> - Never edit a file in `<frozen_paths>` (a hash/contract freeze) unless the brief explicitly authorizes it.
> - Stay in cost budget; if you'd exceed, stop and surface to control.
> - Your session JSONL and the project auto-memory dir are under `~/.claude/projects/<project-slug>/`; write scratch to `/tmp/`, never the worktree.

### 4. Dispatch via assets

Invoke the `assets-dispatch` skill with `<asset-name>` = `issue-<N>` and the prompt file path. Owner-approval fires per the assets config.

### 5. Record the dispatch

Comment on the issue: asset name, session path, cost budget.

### 6. Arm the monitors

Per the `assets` plugin's monitoring steps, arm — as the asset launches —
**`asset-heartbeat`** (persistent; wakes control only on no-visible-progress / permission-prompt / vanished-window — this is what catches a silently-parked asset, since GitHub comments are async and won't re-wake control on their own; the reliable un-park is a tmux `--continue` nudge) and, once the PR opens, **`pr-completion-monitor <PR> "<review-check-name>"`** (wakes on terminal CI state, not comment churn). **Caveat:** a check `bucket=pass` ≠ "no findings" — read the review body after a pass.

## Constraints

- One asset per issue. If `issue-<N>` already exists, surface the existing asset and stop.
- Cost budget MUST be in the brief; the asset aborts + surfaces if it would exceed.
- Control merges (or owner merges); the asset never merges.
- The signal-file `.done` is the lifecycle (async) wake; GitHub issue/PR comments are the decision surface (also async — control reads them via `--check` + the heartbeat).
