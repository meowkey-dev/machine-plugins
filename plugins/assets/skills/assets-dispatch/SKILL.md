---
name: assets-dispatch
description: Spawn or continue an asset (long-running coding agent) in a local or remote tmux session, with signal-file completion monitoring. Trigger on "dispatch asset", "dispatch squad", "spawn agent", or /assets-dispatch.
user-invocable: true
allowed-tools:
  - Read
  - Bash(cat *)
  - Bash(tmux *)
  - Bash(mkdir *)
  - Bash(rm -f *)
  - Bash(sleep *)
  - Agent
---

# /assets-dispatch — Asset Lifecycle Management

Spawn new coding agents or manage existing ones in a local tmux session. Agents ("assets") run in
dedicated tmux windows, report completion via signal files, and are monitored via a background
health check so the controlling session stays responsive.

**Controller-asymmetric:** install lives on the controller side. The asset is a generic agent
session (claude / codex / gemini / etc.) that receives instructions via tmux send-keys — no
install on the asset side. For bidirectional / persistent / multi-peer controller↔asset comms,
see the `mesh-channel` plugin SKILL — same use-case space, different shapes (see comparison table in `mesh-channel`'s SKILL).

## Arguments

```
/assets-dispatch <name> <prompt-file>               — new asset with prompt file
/assets-dispatch <name> --continue "message"        — send a follow-up instruction to an existing asset
/assets-dispatch <name> --btw "question"            — ask a side question without redirecting the task
/assets-dispatch <name> --check                     — check the asset's current status
/assets-dispatch <name> --recall                    — exit and kill the asset window
```

## Flags (new dispatch only)

- `--launcher <command>` — which agent CLI to use (default: first launcher in config)
- `--safe` — keep interactive permission prompts (disables yolo mode)
- `--teams` — enable experimental agent teams
- `--model <model>` — override model (e.g. `claude-opus-4-6[1m]`)
- `--monitor signal` — poll `<signals>/<name>.done` every few seconds (default)
- `--monitor cron <minutes>` — check back after N minutes via background timer
- `--no-monitor` — skip monitoring setup

## Steps

### 0. Config resolution (do this first, for every operation)

Read config in resolution order — merge field-by-field (local overrides global):

1. `<repo-root>/.claude/assets/config.yaml` — walk up from cwd to find the repo root.
   Legacy `<repo-root>/.assets/config.yaml` is honored as a back-compat fallback (with a
   stderr deprecation warning); dropped in v0.4.0.
2. `~/.claude/plugins/assets/config.yaml` — global user config, fallback
3. Env vars — ultimate per-field fallback:

| Field | Env var |
|---|---|
| `tmux.socket` | `ASSETS_TMUX_SOCKET` |
| `tmux.session` | `ASSETS_TMUX_SESSION` |
| `paths.workdir` | `ASSETS_WORKDIR` |
| `paths.signals` | `ASSETS_SIGNALS_DIR` |

Optional remote fields (when `tmux.remote` is set, the plugin manages an SSH socket-forward):

| Field | Purpose |
|---|---|
| `tmux.remote.host` | SSH target for the remote tmux server |
| `tmux.remote.socket` | Remote-side tmux socket path |
| `tmux.remote.ssh_opts` | Optional extra SSH arguments (e.g. `["-i", "~/.ssh/key"]`) |

If neither config file exists and no env vars are set, error with:
```
No config found. Run /init-assets-config to scaffold one (repo-local <repo>/.claude/assets/config.yaml by default, or --global for ~/.claude/plugins/assets/config.yaml).
```

Required fields: `tmux.socket`, `tmux.session`, `paths.workdir`, `paths.signals`. Error on missing required fields.

**Launchers:** The `launchers` list is read from whichever config file provides it (local first, then global — not merged). Surface the list of `{command, rule}` pairs to help choose the right launcher per task.

**Bundled dispatch-asset path:**
- Check `config.paths.launcher` — if set, use that script
- Otherwise: `${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset` — resolves relative to the plugin's own
  install dir, so it is correct for BOTH a marketplace-cache install
  (`~/.claude/plugins/cache/<marketplace>/assets/<version>/bin/dispatch-asset`) and a standard
  install. Use the same `${CLAUDE_PLUGIN_ROOT}/bin/…` form the Step 6/9/13 sibling helpers use —
  do NOT hardcode `~/.claude/plugins/assets/bin/…`, which does not exist on cache installs.
- Fallback: `dispatch-asset` in PATH

---

### New dispatch

1. **Check resources.** Ensure the machine has enough RAM for another agent session (check
   available memory via `free -h` or equivalent). Warn if memory is low.

2. **Choose launcher.** If `--launcher <command>` is not specified, use the first launcher in config.
   Show the available launchers and their rules so the right one can be picked for the task.

3. **Propose model.** Unless `--model <id>` was explicitly passed, propose a model alongside the
   launcher. Model choice should reflect task complexity:
   - Heavier reasoning, long-horizon work, or cross-file refactors → opus-tier
   - Routine, repetitive, or narrowly-scoped work → haiku-tier
   - Default / general-purpose → sonnet-tier

   Surface the proposed model ID alongside the launcher in the confirmation message, e.g.:
   "Dispatching `<name>`: launcher=`claude`, model=`claude-opus-4-7[1m]` (reasoning: long-horizon
   refactor with cross-file dependencies). OK?"

   The user can override either choice. Pass the chosen model through to `dispatch-asset` via
   `--model <id>`.

4. **Completion-signal plumbing.**

   **Claude-family launcher (default behavior, v0.4.0+):** completion is harness-emitted.
   `dispatch-asset` injects CC hooks at launch time so the asset's own harness writes
   `boot` / `activity` (mtime touch) / `turn_end` / `exit` events to `<signals>/<name>.jsonl` and
   `<signals>/<name>.activity` deterministically — no prompt mutation required. Skip this step
   entirely; the prompt file is unchanged. (Disabled by `monitoring.harness_signals: false` or
   `ASSETS_HARNESS_SIGNALS=false` — in that case, fall through to the non-claude path below.)

   **Non-claude launcher (codex / aider / etc.):** harness hooks do not apply; completion still
   rides the prompt. Read the prompt file and confirm it contains an instruction like:
   ```
   When you finish, write a one-line summary to <config.paths.signals>/<name>.done
   ```
   Signal file convention: use `<signals>/<name>.done` for general tasks; for code work you may also
   use `<signals>/<repo>-swe.events` to align with SWE conventions.

   **If missing, mutate the prompt file BEFORE approval** so the user reviews the final state:
   - Append the instruction inline (do not rewrite existing content).
   - In the approval prompt (next step), explicitly state "I appended a signal-file instruction to
     `<prompt-file>` — see the final state."
   - Alternative if you can't append (read-only fs, permission denied): abort with a clear error
     asking the user to add the instruction manually.

   Without this instruction, the non-claude asset finishes silently and there is no event to monitor.

5. **Get approval** if `config.approval.new_dispatch == "required"` (the default). The approval
   mechanism depends on `config.approval.style`:
   - `ui` (default): trigger the standard Claude Code permission prompt UI — the user approves or
     denies via the interactive permission flow.
   - `verbal`: ask the user in the chat conversation ("Dispatch asset `<name>` via `<command>`?")
     and wait for a conversational yes/no before proceeding.

   Show: asset name, **final prompt file path** (after any Step 4 mutation), chosen launcher,
   proposed model. Wait for explicit OK before proceeding.

6. **Remote pre-flight** (if `tmux.remote` is set in resolved config):
   1. Run `${CLAUDE_PLUGIN_ROOT}/bin/ensure-tmux-forward` — non-zero exit aborts dispatch with the
      helper's error message.
   2. Run `${CLAUDE_PLUGIN_ROOT}/bin/send-prompt <local-prompt-file> <tmux.remote.host>:~/.assets/prompts/<basename>`
      to copy the prompt file to the remote host. (The `~` here is expanded by the remote shell
      / scp protocol at delivery time — different mechanism from the send-keys context in
      Step 9, where the controlling shell is in play.)
   3. **Resolve the remote `$HOME` once and construct an absolute path.** Run:
      ```bash
      remote_home="$(ssh <tmux.remote.host> 'echo $HOME')"
      effective_prompt_path="${remote_home}/.assets/prompts/<basename>"
      ```
      Store `effective_prompt_path` (now an absolute path on the remote, e.g.
      `/home/<remote-user>/.assets/prompts/foo.md`). This avoids relying on local `$HOME`
      matching remote `$HOME` — which only holds when both the username AND the absolute home
      path are identical (so `/home/user` ↔ `/home/user` works, but `/Users/user` ↔ `/home/user`
      silently fails).

   If `tmux.remote` is NOT set (local mode), `<effective-prompt-path>` = the local prompt file
   path as an absolute path (`realpath <local-prompt-file>` if needed; do not use `~`-prefixed).

7. **Verify tmux socket exists:**
   ```bash
   tmux -S <config.tmux.socket> list-sessions
   ```
   Error clearly if the socket is missing — the tmux server must be running.

8. **Create tmux window:**
   ```bash
   tmux -S <config.tmux.socket> new-window -t <config.tmux.session> -n <name> -c <config.paths.workdir>
   ```

9. **Launch** (execute directly — never source; the shell may be fish).

   By construction (Step 6), `<effective-prompt-path>` is an absolute path with no shell
   expansion left to do. Wrap it in **single quotes** inside the outer double-quoted send-keys
   string — single quotes prevent any further expansion and safely handle spaces or shell
   metacharacters without needing to escape:

   ```bash
   tmux -S <config.tmux.socket> send-keys \
     -t <config.tmux.session>:<name> \
     "ASSETS_SIGNALS_DIR='<config.paths.signals>' ASSETS_HARNESS_SIGNALS=<config.monitoring.harness_signals> <dispatch-asset-path> --launcher <command> --name <name> --prompt '<effective-prompt-path>' [--safe] [--teams] [--model <m>]" Enter
   ```

   Always pass `--name <name>` (the tmux window name). The launcher uses it as the label for
   harness-emitted signal files (`<signals>/<name>.jsonl`, `<signals>/<name>.activity`) on the
   claude-family path. Without `--name`, the launcher falls back to `tmux display-message -p '#W'`
   in the dispatched shell, then `unknown-<pid>` — both are noisier than the explicit name.

   **Why the `ASSETS_SIGNALS_DIR=…` / `ASSETS_HARNESS_SIGNALS=…` env prefix is required**:
   `dispatch-asset` runs INSIDE the asset's pane with `cwd=<config.paths.workdir>`, so its
   own `_config.sh` walks up from there — the controller's repo-local config at
   `<controller-repo>/.claude/assets/config.yaml` is **invisible** across the pane boundary.
   Without the env prefix, `SIGNALS_DIR` resolves empty (unless a global config or a
   workdir-local config also exists), and the harness-signal injection silently no-ops.
   Using an **env prefix rather than a new CLI flag** keeps the contract orthogonal to any
   `paths.launcher` custom-launcher delegation (delegated scripts inherit env automatically).
   `dispatch-asset` now emits a stderr warning if it sees `harness_signals=true` with an
   empty `SIGNALS_DIR`, so a missing prefix surfaces immediately rather than hours later.

   Note: `tmux send-keys` is not a remote shell — it sends literal keystrokes to the pane.
   Variable expansion happens in the **controlling shell** (the one running send-keys) before
   keystrokes leave, not in the remote pane. Step 6 makes this irrelevant by always producing
   an absolute path.

   The dispatch-asset script handles workdir cd, `.env` sourcing, agent teams env, model override,
   and yolo mode. Pass through any flags that were given to this skill.

10. **Set up monitoring** per `--monitor` (default: `signal`). The signal stream differs by
    launcher family:

   - `signal` —
     - **Claude family (harness signals on):** wake on `turn_end` or `exit` events in
       `<signals>/<name>.jsonl`. Recommended: a persistent Monitor on
       `tail -n+1 -F <signals>/<name>.jsonl` parsing each line; emit only on
       `"event":"turn_end"` (with the `last_message` excerpt) or `"event":"exit"`.
       `boot` is informational — surface once if absent within the dispatch timeout, then go
       silent. `last_message` carries the asset's actual closing words (truncated to 500 chars),
       which replaces the previous prompted `.done` one-liner.
     - **Non-claude (or `harness_signals: false`):** background poll watching
       `<config.paths.signals>/<name>.done` every `config.monitoring.signal_poll_interval_sec`
       seconds (default: 5s), with a timeout at `config.monitoring.signal_timeout_min` minutes
       (default: 30).
   - `cron <N>` — check back after N minutes.
   - `--no-monitor` — skip.

11. **Health check** — schedule a one-shot check at `config.monitoring.health_check_at_min` minutes
   (default: 10). Use a haiku subagent to peek at the tmux pane (protects the controlling session's
   context window):
   ```bash
   tmux -S <socket> capture-pane -t <session>:<name> -p -S -10
   ```
   Report: is the asset stuck on a permission prompt? Actively working? Already done?

12. **Liveness / no-progress detector.** The one-shot health check (step 11) fires once; the
    signal poll (step 10) only wakes on a `turn_end` / `exit` (claude) or `.done` (non-claude).
    Neither catches an asset that **silently parks mid-task** — e.g. it posts a question / plan
    and idles waiting for a reply. A controller message (mesh-channel, `--continue`) reaches the
    asset only at a **turn boundary**, so a park past the last turn is not re-woken and can go
    unnoticed. Pick by launcher family:

   - **Claude family (harness signals on):** watch `<signals>/<name>.activity` — its mtime
     advances on every tool call (PostToolUse hook). The controller wakes when
     `now - mtime > monitoring.heartbeat_interval_min` (default 30 min) and the most recent JSONL
     event is not `exit`. This is deterministic — no pane heuristics, no spinner-glyph stripping.
   - **Non-claude:** arm `bin/asset-heartbeat` in a **persistent** Monitor:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/bin/asset-heartbeat <name> [interval_sec]   # default: monitoring.heartbeat_interval_min*60, else 1800
     ```
     It peeks the pane every interval and wakes the controller ONLY on **no visible progress**
     (pane frozen — normalized to ignore the rotating spinner glyph + ticking timer, so it
     catches both idle parks AND hung-but-spinning tool calls), a **permission prompt**, or a
     **vanished window**. Pane-freeze is a heuristic, not proof — peek / ask the asset to
     disambiguate on wake.

   The reliable un-park action when either fires is a tmux `--continue` nudge (forces a fresh
   turn that consumes any queued controller message).

13. **PR-completion monitor (for PR-producing workflows).** When the asset opens a PR, wake only on
   terminal CI state — not on every comment-count change — with `bin/pr-completion-monitor`:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/pr-completion-monitor <PR> [highlight_check_name]   # e.g. "claude-review / claude-review"
   ```
   It polls `gh pr checks` and emits when all checks finish (and reports the highlight check's
   verdict, if named). **Caveat:** a check `bucket=pass` does NOT mean "no findings" — a review
   bot's status passes mechanically even when its comment body flags real issues; read the body
   after a pass.

14. **Report:** "Asset `<name>` dispatched via `<command>`. Monitoring: signal + 10 min health check + heartbeat."

---

### Continue existing (`--continue`)

Use `--continue` to send a **follow-up instruction** that the asset should add to its task queue
(i.e., genuine new work). For side **questions** that shouldn't redirect the current task, use
`--btw` instead (next section).

**When to reach for `mesh-channel` instead:** `--continue` and `--btw` are tmux-pane comms —
one-way (controller → asset), single-asset, pane-scrollback only. If you need any of
bidirectional flow (asset signals back to you), persistent log (`cat`/`jq` after the fact),
or multi-peer (more than one asset on the same channel), use the `mesh-channel` plugin's
SKILL instead — same use-case space, different shapes (see comparison table in `mesh-channel`'s SKILL).

1. Verify the window exists:
   ```bash
   tmux -S <socket> list-windows -t <session> | grep <name>
   ```
2. Send the message via tmux send-keys. Handle vi mode if the pane uses it: send `Escape` then `i`
   before the message to ensure insert mode. For long messages, add `sleep 0.5` before the final
   Enter — tmux paste can race with the Enter key, leaving the message as `[Pasted text]` without
   submitting.
3. After Enter, wait 2 s and verify the pane shows the message was accepted (not `[Pasted text #N]`).
4. Re-establish monitoring if `--monitor` was specified.

---

### Side question (`--btw "question"`)

For asking a running asset a **quick question without redirecting** its current task focus,
use Claude Code's built-in `/btw` mechanism. The asset receives the question, answers, and
returns to its prior task — unlike `--continue`, this does not add a new instruction to the
task queue.

**Rule (convention):** `/btw` is for **questions only**. Never use it to send new task
instructions — that creates semantic ambiguity (the asset doesn't know whether to drop, queue,
or fork the work). Genuinely new work goes through `--continue`.

1. Verify the window exists:
   ```bash
   tmux -S <socket> list-windows -t <session> | grep <name>
   ```
2. Send `/btw "<question>"` to the asset pane using the **same robustness trick** as `--continue`
   (vim mode + paste-race handling):
   - Send `Escape` then `i` to ensure insert mode.
   - Send the literal text `/btw "<question>"`.
   - `sleep 0.5` before the final Enter.
   - After Enter, wait 2 s and verify the pane accepted the message (not stuck at `[Pasted text]`).
3. The asset's `/btw` UI shows `f to fork · Esc to close`:
   - `f` — **fork** from the btw point: continue forward with the btw question as the new main
     thread (use only if the question is genuinely a redirection; usually not what you want).
   - `Esc` — close the btw, asset returns to its prior task without acknowledgment in the main
     thread.
   - **Default behavior** (no key sent): asset answers in the pane and continues main task. This
     is what you want for true side questions.
4. Do NOT send `f` or `Esc` automatically — let the asset surface the answer in its pane; the
   controlling agent reads it via `--check` if needed.

---

### Check status (`--check`)

**Remote pre-flight:** If `tmux.remote` is set in resolved config, run `${CLAUDE_PLUGIN_ROOT}/bin/ensure-tmux-forward` first — non-zero exit aborts with the helper's error message.

Use a haiku subagent to capture the last 10 lines of the tmux pane — this protects the controlling
session's context window from raw terminal output:

```bash
tmux -S <socket> capture-pane -t <session>:<name> -p -S -10
```

Report the status concisely: actively working, stuck on a prompt, idle, or done.

---

### Recall (`--recall`)

**Remote pre-flight:** If `tmux.remote` is set in resolved config, run `${CLAUDE_PLUGIN_ROOT}/bin/ensure-tmux-forward` first — non-zero exit aborts with the helper's error message.

1. Send `/exit` + Enter to the asset:
   ```bash
   tmux -S <socket> send-keys -t <session>:<name> "/exit" Enter
   ```
2. Wait 3 seconds.
3. Kill the window:
   ```bash
   tmux -S <socket> kill-window -t <session>:<name>
   ```
4. Clean up signal files and any associated prompt file:
   ```bash
   rm -f <config.paths.signals>/<name>.done       # non-claude prompted-completion shim
   rm -f <config.paths.signals>/<name>.jsonl      # claude harness-emitted lifecycle events
   rm -f <config.paths.signals>/<name>.activity   # claude PostToolUse mtime
   rm -f <config.paths.signals>/.settings/<name>.json   # generated hook settings
   rm -f <config.paths.signals>/<name>.prompt
   ```

---

## Worktree-based dispatch (optional)

When the user wants the squad to work in a **git worktree** — for filesystem isolation
from the main checkout, or to run multiple branches in parallel without conflicts — the
SKILL handles worktree lifecycle; the launcher script stays unchanged.

**Why the SKILL (not the launcher) owns this:** `dispatch-asset` is a dumb shim that just
`exec`s the chosen launcher with a working directory. Git worktree creation is a higher-level
decision (which branch, which path, how to clean up) that the controlling agent has context
for. Keeping worktree management out of the launcher preserves launcher-agnosticism — it
works for any agent CLI, not just `claude` (which has its own `--worktree` flag).

**Path convention:** when dispatching with a worktree, the SKILL **always** composes the
path as

```
<config.paths.workdir>/worktrees/<branch-slug>
```

where `<branch-slug>` is the branch name with `/` substituted to `-` (e.g. `feat/foo` →
`feat-foo`). This eliminates a class of bugs where the controller passes a raw worktree
path that turns out to be read-only in the asset sandbox (observed on `~/tmp/...` paths).
The controlling agent does not pick the path raw — it composes from config that's already
known to be writable.

**On new dispatch with worktree:**

1. **Compose the path from config** (from `paths.workdir` resolved in Step 0):
   ```bash
   BRANCH=<branch-name>
   BRANCH_SLUG="${BRANCH//\//-}"
   WORKTREE_PATH="<config.paths.workdir>/worktrees/${BRANCH_SLUG}"
   ```

2. **Writability pre-flight** — verify the parent directory is writable before any git op
   or dispatch:
   ```bash
   mkdir -p "$(dirname "$WORKTREE_PATH")"
   [ -w "$(dirname "$WORKTREE_PATH")" ] || die "config.paths.workdir parent is not writable: $(dirname "$WORKTREE_PATH")"
   ```
   If the parent isn't writable, abort with a clear error naming `paths.workdir` — don't
   silently let `git worktree add` "succeed" into a path the asset can't commit from.
   (For non-worktree dispatch passing raw `--workdir <path>`, apply the same `[ -w ]`
   check on that path before calling `dispatch-asset`.)

   **Limitation worth knowing:** this check runs from the **controller's** filesystem
   view. The asset sandbox may see different mounts — paths like `~/tmp/` are writable
   for the controller but read-only for the asset in some container setups (observed
   2026-05-22). The pre-flight catches obvious cases (e.g. `/proc/...`, missing parents)
   but not sandbox-asymmetric cases. The **path convention** is the primary defense — it
   keeps you on `paths.workdir` which is configured to be writable in both views.

3. **Create the worktree:**
   ```bash
   git -C <repo> worktree add "$WORKTREE_PATH" "$BRANCH"
   ```
   - If `<branch>` is omitted, git creates a worktree on a new branch named after the
     basename of `$WORKTREE_PATH`.
   - If `<branch>` already exists AND is not currently checked out in another worktree
     (including the main repo), the worktree checks it out.
   - If the branch is **already checked out elsewhere**, `git worktree add` fails with
     `fatal: '<branch>' is already used by worktree at '<other-path>'`. To recover: either
     pick a different branch, remove the conflicting worktree first
     (`git worktree remove <other-path>`), or detach the existing checkout
     (`git -C <other-path> checkout --detach`).

4. **Smoke-test the worktree is git-usable** (catches edge cases where the worktree was
   created but commit-from there will fail — e.g. partial filesystem mounts):
   ```bash
   git -C "$WORKTREE_PATH" status --short >/dev/null || die "Worktree created but git ops fail from $WORKTREE_PATH"
   ```

5. **Sync deps if the worktree is a uv project** (machine#129). A freshly-created
   worktree has no project deps installed, so the asset's first `pytest`/import dies on
   `ModuleNotFoundError` and re-discovers `uv sync` every dispatch. **Gate on lockfile
   presence** so non-uv repos are untouched:
   ```bash
   if [ -f "$WORKTREE_PATH/uv.lock" ]; then
     ( cd "$WORKTREE_PATH" && uv sync --frozen )
   fi
   ```
   `--frozen` mirrors CI (no lockfile mutation). If `uv sync` fails (e.g. a private git
   dep with no credential — see the sdlc dispatch brief's private-git-dep checklist),
   surface the error rather than handing the asset a half-synced worktree.

6. **Invoke `dispatch-asset` with the composed path:**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/dispatch-asset \
       --launcher <command> \
       --prompt <prompt-file> \
       --workdir "$WORKTREE_PATH" \
       [--model <id>]
   ```

7. The launcher's session sees `$WORKTREE_PATH` as its working directory. All edits,
   commits, and PR work happen on the worktree's branch, isolated from main checkout.

**Anti-pattern: do not pass a raw `--workdir <path>` for a worktree.** The convention
above is the whitelist. If you find yourself constructing a worktree path some other way,
stop and either (a) use the SKILL-composed path, or (b) explicitly run the writability
pre-flight from Step 2 on your chosen path before calling `dispatch-asset`.

**On `--recall`:** worktree removal is an **additional step that comes AFTER** the standard
`Recall (--recall)` flow defined above (send `/exit`, wait 3s, kill the tmux window, clean
up signal files). The window MUST be killed first — otherwise `git worktree remove` will
refuse with "fatal: worktree still in use." Sequence:

1. Complete the standard `--recall` steps from the `### Recall (--recall)` section above
   (exit → wait → kill window → clean up signals).
2. Inspect worktree state before prompting:
   ```bash
   git -C <worktree-path> status --porcelain
   ```
   This determines whether removal is safe or destructive.
3. **If the worktree is clean** (empty `status --porcelain` output): prompt the user
   "Remove the worktree at `<worktree-path>`? (clean state, safe to remove)" and on
   approval run:
   ```bash
   git -C <repo> worktree remove <worktree-path>
   ```
4. **If the worktree is dirty** (modified/untracked files present): surface what's
   modified, then ask the user to choose:
   - **(a) Commit or stash first** — user handles it, then re-prompt for removal.
   - **(b) Force-remove (discards uncommitted work)** — run `git -C <repo> worktree
     remove --force <worktree-path>`. Make the destruction explicit in the prompt:
     "Force-removing will discard N modified files: …. Confirm?"
   - **(c) Keep the worktree** — leave on disk; user can re-attach or clean up manually
     later. Default if user declines or is unsure.
5. Never auto-`--force` — only on explicit user choice. Never silently skip when dirty
   either; the user should know there's pending state.

**Note for `claude` launcher:** `claude` has its own `--worktree [name]` flag that creates
a worktree internally. **Do not pass `--worktree` to `claude` via dispatch-asset when the
SKILL has already created a worktree** — that would create a second nested worktree. Use
either the SKILL-managed path (recommended, launcher-agnostic) or `claude --worktree`
directly (claude-only, bypasses the plugin), not both.

## Yolo mode recovery

Writing `.mcp.json` or other config files mid-session silently disables `--dangerously-skip-permissions`
(yolo mode). If a health check finds the asset stuck on a permission prompt AND it was dispatched
without `--safe`:

1. Approve the current prompt: send `Enter` via tmux send-keys.
2. Re-enable yolo: send `Shift+Tab` twice:
   ```bash
   tmux send-keys -t <session>:<name> S-Tab S-Tab
   ```

---

## Important

- **Never spawn assets from the controlling session's cwd** — it will steal the controller's MCP
  connections (see: Anti-patterns in the plugin README). Always use `config.paths.workdir`.
- Verify `config.tmux.socket` exists before any tmux operation.
- Get explicit approval before spawning NEW assets (configurable via `approval.new_dispatch`).
- Continuing, checking, and recalling existing assets does not need approval.
