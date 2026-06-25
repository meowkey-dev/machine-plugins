# machine-plugins

A published subset of the **machine** Claude Code plugin marketplace.

This repository is a **generated build artifact**. Its contents are assembled
from private source and force-pushed here by CI on every change — the history
is not preserved, and the tree is overwritten each publish. It carries the
plugins from the marketplace that are intended for public use.

## Plugins

| Plugin | Description |
| --- | --- |
| `sop-compact` | Hooks-only compaction-survival procedure for Claude Code — promotes durable learnings and writes a handoff snapshot before `/compact`, then points the next session at it. |
| `assets` | Local or remote tmux agent dispatch — spawn, monitor, and recall long-running coding agents in dedicated tmux windows. |
| `sdlc` | Closed-loop software-development-lifecycle harness — takes a GitHub issue to a mergeable PR via dispatched agents, then folds learnings into a per-repo playbook. |
| `mesh-channel` | Two-agent communication over a shared JSONL file — append-only protocol with a per-agent cursor and Monitor-driven event wake. |
| `zulip` | Zulip channel for Claude Code — MCP server bridging Zulip streams + DMs to a session via the Anthropic channel protocol, with access control and dual transport (stdio plugin mode / standalone SSE). |
| `channel-nudge` | Hooks-only console-drift detector — one `Stop` hook covering every channel plugin (discord/zulip/wechat). Parses the transcript once per turn and emits a soft, non-blocking `systemMessage` if the assistant answered a real channel inbound as plain console text instead of calling that channel's reply tool. |

## Install

Add the marketplace, then install any of the plugins:

```
/plugin marketplace add meowkey-dev/machine-plugins
/plugin install sop-compact@machine
/plugin install assets@machine
/plugin install sdlc@machine
/plugin install mesh-channel@machine
/plugin install zulip@machine
/plugin install channel-nudge@machine
```

## Contributing

This repo is a generated artifact — **pull requests are automatically closed.**
If you have a bug report, a feature request, or a change to propose, please
[open an issue](https://github.com/meowkey-dev/machine-plugins/issues) instead.
