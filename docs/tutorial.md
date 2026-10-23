---
title: Your first agent-to-editor review loop
---

# Your first agent-to-editor review loop

This exercise needs no AI account. You will open a line of source from terminal
output and return to exactly where you were reading.

## 1. Prepare your terminal

[Install the plugin](https://github.com/fredfortier/tmux-agent-navigation#install),
then open a tmux session. A **session** contains windows; each window contains
one or more terminal **panes**. The plugin opens a temporary editor pane beside
the pane holding your conversation.

In a shell pane, run:

```sh
mkdir -p /tmp/agent-navigation-demo
cd /tmp/agent-navigation-demo
printf 'first line\ninspect this line\nlast line\n' > example.txt
printf '\nAgent suggests checking example.txt:2:1\n'
```

The second command prints a reference like the ones an agent or compiler emits.

## 2. Open the reference

Press `Ctrl-b`, release the keys, then press `[`. This enters tmux **copy
mode**: keystrokes move through terminal history instead of reaching your shell.
If you changed tmux's prefix, use your own prefix instead of `Ctrl-b`.

Press `?`, type `example.txt`, then press `Enter` to search backward. Use `h`
and `l` to place the cursor inside the filename. Type `g`, then `f`.

Neovim opens `example.txt` at line 2. The editor is **zoomed**, meaning it fills
the tmux window while your original pane remains behind it.

## 3. Inspect, change, and return

You are now looking at the evidence behind the agent's reference. To practice an
edit, press `i`, type a word, then press `Escape`. Type `:w` and press `Enter`
to save. Type `:q` and press `Enter` to close this editor window.

You return to the same scrollback cursor. Press `q` to leave copy mode. Your
shell or agent now receives your keystrokes again. `:q` does not discard
changes: if Neovim reports unsaved data, save it with `:w` or make your own
discard decision. If your editor configuration opens several windows, close
those windows normally.

## 4. Review while the agent continues

Enter copy mode again and find the reference. Type `gn` this time. The editor
appears above the conversation in an equal split. The conversation leaves copy
mode and shows its live bottom, so you can see new output.

Press prefix then `Down` to focus the conversation. Press prefix then `Up` to
return to the editor. Press prefix then `e` to zoom the editor, and repeat to
reveal the conversation. Quit the editor to return to the original pane.

## 5. Use it with your agent

Start your usual terminal AI agent from your project directory. Whenever it
mentions a file, use the same loop: **find reference → open → verify → return**.
No special launcher or prompt is needed. Relative paths resolve using the tmux
pane's directory and nearest Git root. If the agent changes to an unrelated
working directory, ask for an absolute path or consult
[path rules](reference.html).

The goal is to spend fewer keystrokes reconstructing context and more time
checking the code. [Configure your editor](configuration.html) when you are
ready.

[Documentation home](index.html)
