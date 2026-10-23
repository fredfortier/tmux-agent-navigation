---
title: Faster code review from your AI conversation
---

# Read the code without losing the conversation

An AI agent points at a file. You open it at the right line, verify its claim,
and return to your place in the transcript. **tmux-agent-navigation** makes that
small loop quick enough to repeat throughout a coding session.

Use `gf` for focused review, or `gn` to keep the agent's live output below your
editor. Your agent runs normally. The first tested pairing was Codex and Neovim;
visible local references from other agents and terminal tools use the same path.

## Start here

1. [Install the plugin](https://github.com/fredfortier/tmux-agent-navigation#install).
2. [Complete a five-minute tutorial](tutorial.html), without an AI account.
3. [Choose your editor and optional integrations](configuration.html).

## Look up details

- [Keys, path syntax, and resolution rules](reference.html)
- [Fix a navigation problem](troubleshooting.html)
- [Behavior contract and source map](design.html)
- [Extraction review and validation scope](review.html)
- [Source, issues, and contributions](https://github.com/fredfortier/tmux-agent-navigation)

The productivity goal is a shorter human review loop. This tool does not verify
an agent's answer for you; it brings the source evidence closer to the answer.
