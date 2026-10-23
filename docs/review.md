---
title: Extraction review
---

# Extraction review

The first release extracts the workflow introduced by source commits
`94b0663b48`, `9d08f83fe7`, `35989523ce`, and `db4f4518f7`. The original use
case was reviewing Codex output in Neovim from host tmux, including an existing
development container. The standalone product generalizes the visible-reference
workflow to terminal AI agents and text editors.

## Review findings and packaging decisions

| Source coupling                                           | Standalone decision                                                |
| --------------------------------------------------------- | ------------------------------------------------------------------ |
| Installer replaced the full tmux config.                  | Additive TPM/manual plugin entrypoint.                             |
| Helpers assumed fixed home-directory locations.           | Resolve modules and executables from the checkout.                 |
| Editor adapter was a symlink outside the bundle.          | Include the real adapter as a regular file.                        |
| Container paths were inside a particular monorepo.        | Explicit container-side package location; no source-tree paths.    |
| A devcontainer config file forced container routing.      | Local by default; opt-in foreground detection only.                |
| Detector required a specific Compose service name.        | Verify running identity and workspace label.                       |
| Host preview bypassed the user's editor config.           | Load ordinary Neovim config; offer a custom-editor argv interface. |
| Reuse checked workspace but not exact container identity. | Refuse reuse when the detected container changes.                  |
| Status text assumed Ctrl-b.                               | Optional status format says prefix and preserves user styling.     |

The parser keeps terminal text as data through argv/JSON boundaries. The review
found no demonstrated shell injection in those source paths. Packaging retains
that discipline and adds custom-adapter argv checks. This is a focused review,
not a claim of an independent security audit.

## Release evidence

`make test` exercises the parser, attached-terminal `gf` and `gn`, editor reuse,
line/column targets, directories, parent copy-mode restoration, original zoom,
custom adapter arguments, and literal shell-like filenames. Optional
`make test-thumbs` adds lowercase-copy and uppercase-open acceptance against
upstream thumbs. GitHub Actions records checks at each published commit.

The original container proof was repository-specific. Its extraction is marked
experimental: no standalone live-container acceptance is claimed. macOS, GUI
editors, and every possible user Neovim configuration are not covered by Linux
CI.

## Discoverability decision

The name **tmux-agent-navigation** puts the platform and task in the repository
name. Its description, topics, README, and docs describe the same narrow
promise. This follows the readable naming and metadata advice in
[Lyra's GitHub SEO guide](https://www.trylyra.ai/blog/github-repo-seo/) and
[SeoWiki's GitHub SEO guide](https://seowiki.org/github-seo/), checked during
packaging. These sources informed naming; they do not guarantee search rankings.
GitHub's
[topic documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)
also explains topic-based discovery. No unrelated keywords or ranking promises
are part of the package.

[Documentation home](index.html)
