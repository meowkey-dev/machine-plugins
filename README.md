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

## Install

Add the marketplace, then install any of the plugins:

```
/plugin marketplace add meowkey-dev/machine-plugins@main
/plugin install sop-compact@machine-plugins
/plugin install assets@machine-plugins
/plugin install sdlc@machine-plugins
/plugin install mesh-channel@machine-plugins
```

## Contributing

This repo is a generated artifact — **pull requests are automatically closed.**
If you have a bug report, a feature request, or a change to propose, please
[open an issue](https://github.com/meowkey-dev/machine-plugins/issues) instead.
