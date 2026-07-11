# Portable Codex subagents

This repository packages the custom Codex agents and routing rules used by this
machine. It intentionally excludes `config.toml`, credentials, and project data.
The manual global-instructions example is in `templates/AGENTS.md.template`.

## Install

```sh
./install.sh
```

The installer copies the agent definitions to `${CODEX_HOME:-$HOME/.codex}/agents`,
installs `rules/SUBAGENT_ROUTING.md` as `SUBAGENT_ROUTING.md`, and adds a managed
import block to `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`. Existing files are
backed up before replacement. A state manifest records ownership, so
pre-existing identical files and modified managed files are preserved.
Re-running the installer is safe; removed definitions are cleaned up only when
their prior installed bytes are unchanged.

Set `CODEX_HOME` to install into a non-default Codex home.

## Uninstall

```sh
./uninstall.sh
```

Uninstall removes only files recorded by this installer and still matching the
installed bytes, and removes only its exact managed block from `AGENTS.md` after
creating a backup. User edits and surrounding bytes are preserved.

Agent TOML files are validated with Python's standard-library `tomllib` when
available.
