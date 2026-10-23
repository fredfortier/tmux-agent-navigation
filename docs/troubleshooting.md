---
title: Troubleshooting
---

# Troubleshooting

## Nothing happens after gf

Confirm you are in tmux **vi copy mode**, with the cursor on an existing local
reference. `gf` means two sequential keys without the prefix. Run:

```sh
tmux show-option -g mode-keys
tmux list-keys -T copy-mode-vi g
tmux list-keys -T agent-navigation-g
command -v nvim jq tmux
nvim --version
tmux -V
```

The controller reports failures as tmux messages. Press prefix then `~` to see
message history. To reproduce parser errors directly from the correct directory:

```sh
~/.tmux/plugins/tmux-agent-navigation/bin/agent-navigation parse 'README.md:1' 3
```

The final argument is a zero-based display-cell offset in the reference.

## The wrong file or no file opens

Use an absolute path to rule out directory ambiguity.
`tmux display-message -p '#{pane_current_path}'` shows the host base directory.
A container shell's cwd cannot be inferred after it changes directories; use
absolute container paths. The plugin deliberately does not search the whole
repository by basename.

A literal filename wins over a line suffix. HTTPS links and Markdown section
anchors are not local file references.
[Review the syntax rules](reference.html).

## A wrapped link fails

Widen the pane or place the cursor on the destination. Wrapping is bounded to
sixteen rows on either side. Thumbs has a simpler matcher; use `gf` for rich
Markdown and paths containing spaces.

## Quitting does not return

`:q` closes one editor window. Close additional windows normally; save modified
buffers if requested. If an editor plugin changes quit behavior, compare with a
minimal Neovim configuration. The child removes a `q` command-line abbreviation,
but does not override every editor mapping. Custom adapters must wait until
their editor exits; backgrounding an editor causes an immediate return.

## Editor still starting or runtime changed

Wait for startup to finish before reopening. If you changed editor, workspace,
or container identity, close the existing child before opening another
reference. Reuse intentionally refuses to send a path to the wrong runtime.

## Key conflicts or status changes

Check the documented `g`, prefix `e`, and optional prefix `F` ownership. Load
your own replacement bindings after the plugin if needed. Status is opt-in and
does not contain a hardcoded prefix. Reloading config does not undo old
bindings; restart tmux when sessions permit after uninstalling.

## Reporting a bug

Include tmux and Neovim versions, OS, installation method, minimal tmux config,
reference spelling, pane cwd, expected result, and any tmux error. State whether
it happens with an isolated Neovim config. Replace private paths and never
attach a complete agent transcript, environment, Docker arguments, or tokens.
Use the
[issue template](https://github.com/fredfortier/tmux-agent-navigation/issues/new/choose).

[Documentation home](index.html)
