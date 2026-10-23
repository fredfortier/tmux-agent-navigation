# tmux-agent-navigation

[![CI](https://github.com/fredfortier/tmux-agent-navigation/actions/workflows/ci.yml/badge.svg)](https://github.com/fredfortier/tmux-agent-navigation/actions/workflows/ci.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Go from an AI agent's file reference to your text editor—and back to the same
conversation.**

AI agents produce answers faster than you can verify them. This tmux plugin
shortens that review loop: open a referenced file at its line, inspect or edit
the code, then return without hunting through scrollback. Keep the agent visible
in a split or focus on the file. No agent API, prompt integration, or special
agent launcher.

```text
Agent output: src/server.lua:42:3
      ↓ copy mode → gf             ↓ copy mode → gn
┌─────────────────────────┐   ┌─────────────────────────┐
│ Editor at line 42       │   │ Editor at line 42       │
│                         │   ├─────────────────────────┤
│ :q → same scrollback    │   │ Agent continues below   │
└─────────────────────────┘   └─────────────────────────┘
```

The first tested pairing was **Codex + Neovim**. The workflow works with visible
local file references from any terminal AI agent, build log, or command output.
Neovim is the built-in editor; other terminal editors use a small
[adapter](https://fredfortier.github.io/tmux-agent-navigation/configuration.html#other-text-editors).
Neovim is still required as the Lua runtime with a custom editor.

## Install

Requires Linux, Bash, **tmux 3.3+**, **Neovim 0.11+**, and **jq** on `PATH`.
Linux is the supported platform; macOS is not yet verified. No npm, Python, or
Neovim plugin manager is needed at runtime.

With [TPM](https://github.com/tmux-plugins/tpm), add before TPM's
initialization:

```tmux
set -g mode-keys vi
set -g @plugin 'fredfortier/tmux-agent-navigation'
```

Reload your tmux config, then press **prefix + I** (capital i) to install. The
default prefix is `Ctrl-b`; your existing prefix works too.

Or install manually:

```sh
git clone https://github.com/fredfortier/tmux-agent-navigation \
  ~/.tmux/plugins/tmux-agent-navigation
```

Add to `~/.tmux.conf` (or your existing XDG tmux config), then reload it:

```tmux
set -g mode-keys vi
run-shell '~/.tmux/plugins/tmux-agent-navigation/agent-navigation.tmux'
```

This adds bindings to your configuration. It does not replace your config,
theme, clipboard settings, or editor plugins. It takes over copy-mode `g`,
prefix `e`, and, when enabled, prefix `F`; see
[configuration](https://fredfortier.github.io/tmux-agent-navigation/configuration.html).

## Your first review loop

1. Inside tmux, run your AI agent normally from the project directory. Or try
   `printf '%s\n' 'README.md:1'` from this checkout—no AI account needed.
2. Press `Ctrl-b`, release both keys, then press `[` to enter **copy mode**:
   tmux's keyboard-controlled scrollback view.
3. Move with `h`, `j`, `k`, `l`. Use `/README` then `Enter` to find a reference.
   Place the cursor anywhere on `README.md:1`.
4. Type `gf` to open the file in a zoomed editor. In Neovim, press `i` to edit,
   `Escape` to stop inserting, then `:w` and `Enter` to save.
5. Type `:q` and `Enter` to close the editor. You return to the same copy-mode
   position. Press `q` to leave copy mode and talk to the agent again.

Try `gn` instead of `gf` to keep the live conversation below the editor. `gn`
exits the conversation's copy mode so new output remains visible. Use `Ctrl-b`
then an arrow key to move between panes. Repeat this loop for each claim or
change you want to check: less navigation, more time reading the actual code.

| Keys                 | Result                                                                  |
| -------------------- | ----------------------------------------------------------------------- |
| `gf` in vi copy mode | Open file or directory; zoom editor; preserve scrollback.               |
| `gn` in vi copy mode | Open editor above the live conversation in an equal split.              |
| `gg` in vi copy mode | Go to the beginning of scrollback.                                      |
| prefix then `e`      | Toggle editor zoom and conversation visibility.                         |
| `:q` in Neovim       | Return to the conversation; ordinary unsaved-buffer checks apply.       |
| prefix then `F`      | Optional [tmux-thumbs](https://github.com/fcsonline/tmux-thumbs) hints. |

## What opens?

Existing local files and directories: `src/app.lua:42:3`, `src/app.lua#L42-L50`,
`[source](src/app.lua#L42)`, quoted paths with spaces, and
`app.lua (src/app.lua)`. Ranges open at their first line. Relative paths resolve
from the pane directory, then its nearest Git root. Exact filenames win over
punctuation or suffix interpretation. Wrapped references are joined near the
cursor.

HTTPS links, Markdown section anchors, hidden OSC 8 destinations, and
repository-wide basename search are outside the resolver's scope. See the
[reference rules](https://fredfortier.github.io/tmux-agent-navigation/reference.html).

## Documentation and development

- [Beginner tutorial](https://fredfortier.github.io/tmux-agent-navigation/tutorial.html)
- [Configuration, custom editors, and optional containers](https://fredfortier.github.io/tmux-agent-navigation/configuration.html)
- [Troubleshooting](https://fredfortier.github.io/tmux-agent-navigation/troubleshooting.html)
- [Behavior contract and code guide](https://fredfortier.github.io/tmux-agent-navigation/design.html)
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) ·
  [Changelog](CHANGELOG.md)

Run `make test` for parser cases and a disposable attached-terminal integration
suite. `make lint` checks Bash and Lua. Tests never attach to your tmux server.
The container adapter is experimental and requires separate live verification.

[MIT licensed](LICENSE). Built from a working terminal review workflow; the goal
is a faster human verification loop, with no dependency on one AI agent.
