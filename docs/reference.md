---
title: Keys and reference syntax
---

# Keys and reference syntax

## Navigation

| Keys           | Behavior                                                          |
| -------------- | ----------------------------------------------------------------- |
| prefix `[`     | Enter tmux copy mode (tmux's own binding).                        |
| copy-mode `gf` | Open a zoomed child; retain copy mode and its cursor.             |
| copy-mode `gn` | Open an equal split above; exit parent copy mode for live output. |
| copy-mode `gg` | Move to history-top.                                              |
| prefix `e`     | Toggle the current pair's editor zoom.                            |
| Neovim `:q`    | Close a window normally; return after the child exits.            |
| prefix `F`     | Optional thumbs picker: lowercase copies, uppercase opens.        |

Zoom covers the entire tmux window. Other panes remain present. Returning
restores the parent's original zoom state. `gn` is a plugin binding, not Vim's
native `gn`. Opening a reference does not copy it or modify tmux's paste buffer.

## Accepted visible references

| Form                                       | Opens                                           |
| ------------------------------------------ | ----------------------------------------------- |
| `src/app.lua`                              | First line, first column.                       |
| `src/app.lua:42`                           | Line 42.                                        |
| `src/app.lua:42:3`                         | Line 42, byte column 3.                         |
| `src/app.lua:42-50`                        | First line of range: 42.                        |
| `src/app.lua#L42`                          | Line 42.                                        |
| `src/app.lua#L42-L50` or `#L42-50`         | Line 42.                                        |
| `[source](src/app.lua#L42)`                | Line 42, including cursor on the label.         |
| `[nested [label]](<a (b).md#L42> "title")` | File with spaces and parentheses.               |
| `` `a file.txt:2` ``                       | Quoted filename at line 2.                      |
| `app.lua (src/app.lua#L42)`                | Annotated path when label matches its basename. |
| `src/`                                     | Directory browser.                              |

Markdown supports balanced parentheses, nested labels, backslash escapes,
percent-encoded filenames, and optional quoted or parenthesized titles. The
cursor can be anywhere within the link. Angled and quoted plain paths allow
spaces. Sentence punctuation is stripped only after exact spellings fail.

## Resolution order

1. Select only reference candidates covering the copy-mode cursor's display
   cell.
2. Try the exact filename before interpreting suffixes or decoding escapes.
3. Try its line/column suffix; try decoded and prose-trimmed variants as
   fallbacks.
4. Resolve absolute paths directly; expand `~/` in the active runtime's home.
5. Resolve relative paths from the pane directory, then its nearest Git root.
6. Require an existing regular file or directory; report a visible error
   otherwise.

The nearest Git root recognizes `.git` directories and worktree `.git` files.
References are relative to terminal context, not the Markdown document
containing them. There is no filesystem-wide basename lookup. Plain `file://`
URLs, HTTPS repository links, reference-style Markdown definitions, section
headings, and hidden OSC 8 destinations are unsupported. Malformed line anchors
fail.

`gf` and `gn` reconstruct soft wraps within sixteen physical rows of the cursor.
A resize can invalidate tmux's scroll offsets, so the current cursor line
remains authoritative. Very long references outside that range may require a
wider pane. Line and byte-column values are one-based, clamp to available
content, and use the first line of a range. A literal existing filename
containing `#L2` or `:2` wins.

[Documentation home](index.html)
