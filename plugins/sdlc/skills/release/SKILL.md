---
name: release
description: Cut a release tag at a CI-green merged commit, then invoke the `retro` skill for the release-window cross-PR synthesis. Does NOT deploy / arm / promote — those stay human-gated. Trigger on "cut release", "release the current head", or /release.
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Skill
---

# /release [<sha>] — cut a release tag + run the `retro`

Outer-loop skill. Cuts the release tag and triggers the cross-PR playbook update via the `retro` skill. **Cut ≠ deploy** — deploying/arming a release is a separate, human-gated repo-local step (never performed by this skill).

## Procedure

1. **Target sha.** Default = `git rev-parse HEAD`. MUST be an ancestor of `origin/main` (release only from merged main).
2. **Assert CI is green on that exact sha.** At least one check-run exists and every conclusion ∈ {success, neutral, skipped}; any pending / failure / cancelled / timed_out blocks the cut. "Merged" ≠ "shippable" until CI passed on that sha.
3. **Show the release window** to the user:
   - `git log <prev_tag>..<sha> --oneline`
   - `gh pr list --state merged --base main --search "merged:>=<prev_tag_date>" --limit 60`
   - `gh issue list --state closed --search "closed:>=<prev_tag_date>" --limit 60`
4. **Wait for owner OK** on the release cut.
5. **Cut the tag.** Use the repo's `release_cmd` (`.claude/sdlc.toml`) if set; otherwise the generic fallback:
   ```bash
   git tag -a <tag> <sha> -m "Release <tag>" && git push origin refs/tags/<tag>
   gh release create <tag> --target <sha> --generate-notes --title <tag>
   ```
   Tag naming is the repo's choice (e.g. semver `v0.1.0` auto-bumped from the latest tag).
6. **Invoke `/retro --window <prev_tag>..<sha>`** for the cross-PR synthesis — it spawns a subagent to read the window's merged PRs + closed issues + git, then opens a single playbook PR with higher-order patterns the per-PR `review` passes wouldn't have caught.
7. **Surface the playbook PR URL** to the owner.
8. **Stop.** Deploy / arm / promote are separate human-gated steps (especially when `prod_gated = true`).

## Constraints

- Never auto-deploy / auto-arm / auto-promote.
- The release tag is durable; only cut after owner approval + green CI on the exact sha.
- The playbook-update PR is a normal PR — bot review + `qa` apply.
- One playbook PR per release.

## Relation to `review`

`review` is the **per-PR** skill that fires on every merge — it consumes one asset's `## Report` and applies playbook deltas continuously. `retro` (this skill's downstream) is the **per-release** skill — it synthesizes across the full window of already-merged workstreams for higher-order patterns no single PR's report would surface alone. By the time `/release` runs `retro`, the per-PR `review` passes have already drained the single-PR lessons; the retro's job is the cross-cutting residue.
