---
title: Behavior contract and code guide
---

# Behavior contract and code guide

## Public behavior contract

These are the compatibility obligations for this package. A change that breaks
one requires a documented compatibility decision and a changelog entry.

- Terminal references are data. Captured text must never become shell code.
- Navigation opens only existing local files or directories in the chosen
  runtime.
- `gf` preserves parent copy mode and its position; `gn` explicitly exits it to
  show live output. Both focus the requested editor location.
- Each originating pane owns at most one reusable child. Neovim reuse must match
  runtime, workspace, and container identity; custom adapters require closing
  first.
- Exiting the child returns focus to a surviving parent and restores its
  original zoom state after tmux removes the child pane. A missing parent is
  harmless.
- No forced buffer discard, automatic save, agent API call, clipboard write
  during opening, container lifecycle action, or replacement of user
  configuration occurs.
- Plugin setup owns only the documented key bindings and its namespaced options.
  Optional thumbs setup also owns its documented upstream integration options.
- Errors are visible in tmux and return a nonzero controller exit status.

The supported baseline is Linux, Bash, tmux 3.4+, Neovim 0.11+, and jq. Custom
editors still require Neovim for the controller. Optional
`@agent-container-root` routing maps checkout paths into one existing container;
`@agent-nvim-config` selects only the host child configuration. The custom
adapter interface is three argv values: absolute target path, one-based line,
one-based byte column. Adapters must remain in the foreground until closing.
Private Lua functions, JSON payload fields, RPC names, and `@nav_*` pane options
are internal interfaces.

## Source map

| File                    | Responsibility                                                           |
| ----------------------- | ------------------------------------------------------------------------ |
| `agent-navigation.tmux` | Additive TPM/manual entrypoint, bindings, optional hints.                |
| `bin/agent-navigation`  | Locate checkout; launch the isolated Neovim Lua controller.              |
| `lua/resolve.lua`       | Cursor-aware reference parser and filesystem resolution.                 |
| `lua/navigation.lua`    | Capture scrollback, select runtime, own pane lifecycle and reuse.        |
| `lua/editor.lua`        | Configure the child Neovim and expose its private open operation.        |
| `bin/child-editor`      | Dispatch editor; own temporary socket cleanup and return trap.           |
| `lua/context.lua`       | Opt-in foreground Dev Containers process detection.                      |
| `bin/container-editor`  | Launch Neovim inside an existing container.                              |
| `bin/thumbs-pick`       | Preserve hint origin and invoke upstream thumbs.                         |
| `tests/context.lua`     | Docker selection boundary: exact workspace and absent/ambiguous targets. |
| `tests/parser.lua`      | Reference spelling, every cursor cell, failures, literal filenames.      |
| `tests/integration.lua` | Real PTY key dispatch, file/cursor, layouts, reuse, return.              |
| `tests/adapters.lua`    | Custom-editor argv, return, and setup idempotence checks.                |
| `tests/run`             | Disposable tmux server, attached PTY, isolated editor config, cleanup.   |

## Data and lifecycle

The plugin binds keys to an absolute controller path. The controller captures
only nearby copy-mode text and resolves the reference. It passes an encoded JSON
payload as one tmux exec argument to a child shell, which starts the editor. The
built-in adapter exposes `TerminalNavOpen` on a private Neovim socket so a
second reference can reuse the editor without creating another pane.

When the child exits, a shell trap schedules restoration. tmux removes the child
and automatically unzooms its window, so the restorer waits for removal before
restoring the parent's original zoom. Restoring earlier would race pane removal.

Shell calls use argv arrays; the few tmux `run-shell` commands quote the package
path. Filenames are escaped for Neovim commands and encoded for RPC expressions.
Temporary socket directories use `mktemp` and private permissions. No persistent
transcript, environment dump, or command-line log is written.

## Verification boundaries

Parser tests exercise displayed cursor cells, Unicode, punctuation, literal
special filenames, Markdown, invalid anchors, missing targets, and Git
worktrees. PTY tests drive actual client key bindings and inspect the real
editor through RPC. Custom adapter tests inspect separate argv values and return
behavior. CI runs the supported minimum Neovim line and stable Neovim on Linux,
plus Bash and Lua lint. The docs build on pull requests; deployment is
master-only.

Optional thumbs acceptance requires a built upstream checkout. The container
adapter requires a real already-running container and remains experimental until
separate live acceptance is recorded. Passing local navigation tests does not
establish container, GUI-editor, or arbitrary user-plugin compatibility.

[Documentation home](index.html)
