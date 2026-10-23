---
title: Configuration and editor integrations
---

# Configuration and editor integrations

Set plugin options before loading `agent-navigation.tmux` or initializing TPM.
Reload your tmux configuration after changing them. Runtime requirements are
Linux, Bash, tmux 3.4+, Neovim 0.11+, and jq. Core navigation has no network
calls.

## Bindings and status

The plugin installs a vi copy-mode `g` prefix table with `gf`, `gn`, and `gg`;
it also binds prefix `e`. Existing custom bindings for those keys are replaced.
It does not change `mode-keys`: enable vi mode in your tmux config.

```tmux
set -g mode-keys vi
```

Inside the temporary `g` table, `Escape` returns to the normal key table and `q`
cancels copy mode. Press `gg` for history-top. Emacs copy mode is not supported.

Status display is opt-in. Insert the following format into your own status line:

```tmux
set -g status-left '#{E:@agent-status} [#S] '
set -g status-left-length 70
```

The indicator shows `EDITOR`, the return command, and whether prefix `e` will
split or zoom. It uses your existing status styling and your configured prefix.

## Neovim

The built-in adapter loads your ordinary Neovim configuration. It changes only
its child session: disables swap files, sets cwd to the target's nearest Git
root, places the cursor at the requested line and byte column, opens folds, and
centers the view. Outside Git, cwd is the target directory or file's parent.
Directories use netrw. No LazyVim installation is required.

The adapter removes a `:q` command-line abbreviation, including after LazyVim's
`VeryLazy` event, to preserve native window closing. It does not overwrite
normal-mode mappings or force-quit buffers. Your plugins may still affect editor
startup, file opening, and quitting. Short child sessions have no swap recovery.

Another reference from the same conversation reuses its child through a private
Neovim socket. Buffer changes retain Neovim's unsaved-change protections.

To use a separate configuration for host-only previews, set an absolute init
path (or `NONE`) before loading the plugin:

```tmux
set -g @agent-nvim-config '/home/you/.config/tmux/host-preview.lua'
```

This affects built-in host Neovim children only. Container children retain their
own normal configuration. Close an existing child before changing this option.

## Other text editors

Set `@agent-editor` to an **absolute executable path**. It is one executable,
not a shell command string. The plugin passes three separate arguments:

```text
adapter /absolute/file line byte-column
```

For Vim, save the supplied
[example adapter](https://github.com/fredfortier/tmux-agent-navigation/blob/master/examples/vim-editor)
as an executable, then configure its actual path:

```tmux
set -g @agent-editor '/home/you/.local/bin/agent-vim'
```

An adapter must stay in the foreground until its editor closes; use an editor's
wait mode if needed. It must quote filenames and propagate failures. For a GUI
editor, pane focus and return depend on that editor's wait behavior and are not
verified. Custom adapters receive directories unchanged and decide how to browse
them. Close an existing custom editor before opening another reference; RPC
reuse is exclusive to the built-in Neovim adapter. Container mode currently
requires that built-in adapter. Neovim remains the plugin's parser/controller
runtime.

## Optional tmux-thumbs hints

Install [tmux-thumbs](https://github.com/fcsonline/tmux-thumbs) following its
upstream instructions, then set its checkout path before this plugin loads:

```tmux
set -g @agent-thumbs-path '/home/you/.tmux/plugins/tmux-thumbs'
```

This plugin initializes thumbs and binds prefix `F`: lowercase hints copy;
uppercase hints open a zoomed editor. Do not also initialize thumbs later
through TPM, which can replace these options. Thumbs owns its rendering and
clipboard transport settings. Its path expression is simpler than `gf`'s parser:
prefer `gf` for spaces, rich Markdown, and wrapped scrollback.

## Experimental existing-container attachment

The portable default is local navigation. Container detection is opt-in and
Linux-only; it inspects `/proc` and the originating pane's foreground process
chain for an ordinary `devcontainer exec`. It requires host Docker and Dev
Containers CLI, plus Bash, jq, Neovim, and a copy of this package inside the
already-running container. The container needs an accessible
`devcontainer.local_folder` host-workspace label.

Set the absolute **container-side** package path in tmux's server environment:

```sh
tmux set-environment -g TMUX_AGENT_CONTAINER_PACKAGE /src/.tools/tmux-agent-navigation
```

This path is an example, not a required mount point. Put the package there
yourself using your existing development setup. Start your normal
`devcontainer exec` in that pane. Relative references use the container exec's
default working directory; after `cd` inside its interactive shell, use absolute
references. `~/` resolves in the container. Both parse and editor commands
target the detected container ID. No automatic host-to-container path
translation is performed.

For projects whose host checkout is mounted at a known container path, you can
also opt into checkout routing:

```tmux
set -g @agent-container-root '/src'
```

Use the actual container workspace path; `/src` is an example. With this option
and `TMUX_AGENT_CONTAINER_PACKAGE` set, project references in a host pane whose
nearest Git root contains `.devcontainer/devcontainer.json` open in its existing
running container. Exactly one container must carry that checkout's
`devcontainer.local_folder` label; absent or ambiguous targets fail. Host
checkout paths translate to the configured container root. Container-root paths
shown in host output translate back to the checkout only to identify the
project; the mapped target must also exist inside the container. Paths
outside that checkout still use the host editor. Foreground `devcontainer exec`
detection takes precedence. Relative container references use the configured
workspace root.

For read-only foreground-context inspection, run the public controller with the
originating tmux pane ID:

```sh
~/.tmux/plugins/tmux-agent-navigation/bin/agent-navigation context %1
```

It prints the selected foreground container and host workspace as JSON, or
`null` outside a foreground container exec. It neither selects a checkout
fallback nor opens an editor.

For attachment checks without depending on private pane options or socket paths,
`agent-navigation status %1` returns a JSON snapshot for the parent/editor pair.
`parent` contains `pane`, `active`, `copy_mode`, `cursor` (a copy-position
token), and `zoomed`. `editor` is `null` after exit, or contains `pane`,
`runtime`, `container`, `active`, `zoomed`, and `ready`. A ready built-in Neovim
editor also reports `buffer`, `line`, `column`, `cwd`, `pid`, and `filetype`.
The package owns all RPC details; custom-editor state reports `ready: false`.

The adapter never creates, builds, starts, or recreates containers and adds no
mounts. A socket is created privately inside each namespace; it is not shared.
Close an editor before changing containers or switching between host and
container contexts. Ambiguous detection fails rather than choosing a background
job or another pane. Disable the integration with:

```sh
tmux set-environment -gu TMUX_AGENT_CONTAINER_PACKAGE
```

This extracted adapter has not received standalone live-container acceptance.
The source workflow was first exercised with Codex and Neovim in a development
container; that evidence does not establish compatibility with every container.

## Update and uninstall

Use TPM's update/remove commands, or `git pull --ff-only` in a manual checkout.
Close temporary editors before updating. To uninstall manually, remove the
`run-shell` line, custom status reference, and optional integration settings;
then reload your config and restart tmux when your sessions permit. Reloading
alone does not undo installed bindings. Restore your previous `g`, `e`, or `F`
bindings if you customized them. No automatic config or backup files are
created.

[Documentation home](index.html)
