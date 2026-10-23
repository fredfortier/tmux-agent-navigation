# Security policy

Only the latest release receives fixes. Report suspected vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/fredfortier/tmux-agent-navigation/security/advisories/new).
Do not disclose exploit details in a public issue before maintainers can assess
it. If private reporting is unavailable, open an issue requesting a private
contact without including vulnerability details.

The plugin treats terminal references as data and opens only existing local
files or directories. Your chosen editor loads its normal configuration and
plugins, with their normal trust implications. Custom adapters are executable
programs you choose and trust. The optional container detector reads foreground
process metadata and Docker labels; it must never log command lines or
environment values, which can contain secrets.

There is no telemetry, agent API integration, transcript storage, container
lifecycle management, or remote URL fetching in core navigation. Loading a
plugin is code execution; review third-party plugins and updates before use.
