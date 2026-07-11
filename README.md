# Portable Codex subagents

This repository packages the custom Codex agents and routing rules used by this
machine. It intentionally excludes `config.toml`, credentials, and project data.
The manual global-instructions example is in `templates/AGENTS.md.template`.

## Install

```sh
./install.sh
```

The installer copies the agent definitions to `${CODEX_HOME:-$HOME/.codex}/agents`,
installs `rules/SUBAGENT_ROUTING.md` as `SUBAGENT_ROUTING.md`, adds a managed
import block to `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`, and enables
`[features.multi_agent_v2]` in `config.toml` only when that table is absent.
Existing files are backed up before replacement or config modification. A state manifest records ownership, so
pre-existing identical files and modified managed files are preserved.
Re-running the installer is safe; removed definitions are cleaned up only when
their prior installed bytes are unchanged.
An exact standard table header (including whitespace around the dot) is checked
for presence without parsing when no multiline-string delimiters are present;
that path intentionally does not validate the rest of `config.toml` and leaves
it byte-identical. Configs containing multiline strings, or without that exact
header, use the parser-required path. The installer
requires Python 3.11+ `tomllib` or the installable `tomli` parser to validate
and inspect the full TOML (including dotted and inline forms). A missing parser
or malformed config on this parser-required path stops installation before any
files are changed.

Set `CODEX_HOME` to install into a non-default Codex home.

## Uninstall

```sh
./uninstall.sh
```

Uninstall removes only files recorded by this installer and still matching the
installed bytes, and removes only its exact managed block from `AGENTS.md` after
creating a backup. User edits and surrounding bytes are preserved.
The installer-added `config.toml` feature block is intentionally left in place
on uninstall; it is never removed or rewritten.

Agent TOML files are validated with Python's standard-library `tomllib` when
available.
