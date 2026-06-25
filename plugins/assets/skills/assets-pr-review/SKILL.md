---
name: assets-pr-review
description: Dispatch an asset to handle a PR review iteration loop — check comments, fix, push, reply, resolve, repeat until clean. Demonstrates how to build dispatch-derived skills on top of assets-dispatch. Trigger on "dispatch PR review", "assets pr review", or /assets-pr-review.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Bash(mkdir *)
  - Bash(cat *)
  - Bash(rm -f *)
---

# /assets-pr-review — PR Review Squad

Dispatch a coding agent to handle the full PR review iteration loop autonomously:
check comments → fix valid ones → push → reply → resolve → repeat until clean.

This skill demonstrates the dispatch-derived pattern: it generates a structured prompt and
hands it off to `/assets-dispatch`. The asset handles the loop; the controlling session only
relays status.

## Arguments

```
/assets-pr-review <owner/repo> <pr-number> [--launcher <command>]
```

- `owner/repo` — GitHub repository (e.g. `acme/backend`)
- `pr-number` — PR number
- `--launcher <command>` — agent CLI to use; if omitted, inherits the default from assets config

## Steps

1. **Read assets config** (same resolution order as `/assets-dispatch`):
   - `<repo-root>/.assets/config.yaml` > `~/.claude/plugins/assets/config.yaml` > env vars
   - Extract: `paths.signals`, `paths.workdir`, `tmux.socket`, `tmux.session`

2. **Derive names:**
   - `repo-short` — the repo part of `owner/repo` (e.g. `backend`)
   - Asset name: `pr-<repo-short>-<number>` (e.g. `pr-backend-42`)
   - Clone path: `<config.paths.workdir>/pr-review-<repo-short>`
   - Signal file: `<config.paths.signals>/pr-<repo-short>-<number>.done`
   - Prompt file: `<config.paths.signals>/pr-<repo-short>-<number>.prompt` (stable path, not a temp file)

3. **Get approval** — show the asset name, PR target, and launcher; wait for explicit OK.

4. **Generate prompt** — write to `<config.paths.signals>/pr-<repo-short>-<number>.prompt`.
   Using the signals dir (not a temp file) ensures the file outlives the async tmux send-keys
   dispatch: `dispatch-asset` opens the file inside the tmux window after the shell processes
   the command, which happens after `send-keys` returns in the controlling session.

```
PR review iteration for <owner/repo> #<pr-number>.

Setup:
  git clone git@github.com:<owner/repo>.git <config.paths.workdir>/pr-review-<repo-short>
  cd <config.paths.workdir>/pr-review-<repo-short>
  gh pr checkout <pr-number>

Loop:
  1. Check for unresolved review comments:
       gh api repos/<owner/repo>/pulls/<pr-number>/comments \
         --jq '[.[] | select(.in_reply_to_id == null)] | length'
  2. For each new comment:
       - Read the comment and the referenced code
       - If valid: fix the code, commit, push
       - If not valid: reply explaining the disagreement
       - Reply to the comment thread
       - Resolve the thread via GitHub GraphQL API
  3. Run tests if available
  4. Wait 10 minutes, then check again
  5. Repeat until two consecutive clean checks (no new comments)

Rules:
  - Only address comments that make sense. Dismiss nitpicks on pre-existing code.
  - Always resolve conversation threads after replying.
  - Push changes to the PR branch directly.
  - Use "Closes #<pr-number>" pattern in commit messages if applicable.

When done, write a one-line completion summary to <config.paths.signals>/pr-<repo-short>-<number>.done
```

5. **Dispatch** using `/assets-dispatch`:
   ```
   /assets-dispatch pr-<repo-short>-<number> <config.paths.signals>/pr-<repo-short>-<number>.prompt [--launcher <command>]
   ```
   The assets-dispatch skill handles tmux window creation, monitoring, and health check setup.

6. **Prompt file lifecycle** — leave the `.prompt` file in place until `/assets-dispatch ... --recall`
   is run. The `--recall` step can clean it up alongside the signal file.

## Important

- Asset name: `pr-<repo-short>-<number>` — e.g. `pr-backend-42`
- The asset handles the full loop autonomously. The controlling session only needs to relay status.
- Signal file monitoring via `/assets-dispatch` covers completion notification.
- For repos requiring a specific launcher (different auth backend), pass `--launcher <command>` explicitly.
