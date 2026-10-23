# Contributing

Keep the human review loop small: open the referenced source, inspect it, and
return to the conversation. Read the [behavior contract](docs/design.md) before
changing resolution or pane lifecycle.

## Develop

Clone the repo and install Linux, Bash, tmux 3.4+, Neovim 0.11+, jq, ShellCheck,
and StyLua. `script` from util-linux provides the attached test PTY.

```sh
make test
make lint
```

Tests use an isolated tmux server and temporary XDG directories. They do not
attach to your sessions or load your Neovim plugins. Do not point the
integration suite at your own tmux server. Test dependencies are not runtime
dependencies. For optional hint acceptance, build tmux-thumbs using its upstream
instructions:

```sh
TMUX_AGENT_TEST_THUMBS=/absolute/path/to/tmux-thumbs make test-thumbs
```

Use `stylua lua tests` for formatting. Markdown uses mdformat 1.0.0 with GFM and
frontmatter support; CI checks the exact tool versions. The Pages workflow
builds `docs/` with GitHub's Jekyll builder on pull requests and publishes main
only.

## Propose a change

Open a focused issue or pull request describing the user-visible problem and a
small reproduction. Include expected behavior, relevant versions, and
validation. Add parser fixtures for new syntax and a real attached-terminal
check for pane behavior. Avoid tests that merely repeat implementation details.
Include a changelog entry for user-visible changes, and document limitations
honestly.

Do not include agent transcripts, environment dumps, access tokens, or private
paths. Use the [security policy](SECURITY.md) for vulnerabilities. Contributions
are licensed under MIT; submit only code you have the right to contribute.

## Compatibility and releases

The project uses semantic versioning. Before 1.0, minor releases may change the
public behavior contract; patch releases preserve it. Internal Lua/RPC/payload
interfaces are not public APIs. Maintainers release only after CI passes at the
release commit, update the changelog, tag that commit, and publish GitHub notes
with actual validation and known limitations. No automatic version bump or
publication is triggered by a pull request.
