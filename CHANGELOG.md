# Changelog

User-visible changes follow semantic versioning; see
[contributing](CONTRIBUTING.md).

## Unreleased

- Add explicit checkout-to-container routing and namespace mapping for existing
  containers.
- Allow a dedicated host Neovim init while preserving normal container editor
  configuration.
- Expose read-only foreground-context inspection through the controller.

## 0.1.0

- Extract the terminal review loop into an additive tmux plugin with TPM
  support.
- Open visible local references with `gf` or `gn`, including Markdown, line
  anchors, directories, annotations, and nearby soft wraps.
- Preserve scrollback for zoomed review; keep the conversation live in split
  mode.
- Reuse the built-in Neovim child and restore parent focus and original zoom.
- Add a foreground custom-editor interface and optional tmux-thumbs hints.
- Make existing-container attachment opt-in and mark its extracted adapter
  experimental pending standalone live verification.
- Include MIT licensing, a beginner tutorial, behavior contract, and GitHub
  Pages.
- Exercise parser, attached-terminal navigation, and custom-adapter boundaries
  in CI.
