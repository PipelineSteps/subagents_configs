# Portable Codex Subagents

This repository packages portable global Codex subagent definitions and a concise automatic routing policy. It installs into `${CODEX_HOME:-$HOME/.codex}` and intentionally excludes credentials, project data, and personal Codex preferences.

The design keeps the active parent Codex session in charge. There is no dedicated `orchestrator` subagent: the parent understands the full user request, identifies constraints and acceptance criteria, decides whether delegation is useful, sequences specialists, resolves conflicts, inspects final changes, verifies validation, and communicates the result.

## Automatic Routing Design

Every new request is classified silently before action. The parent considers intent, scope and coupling, uncertainty, risk, required permissions, and validation needs, then chooses the least complex reliable execution path.

Defaults are policy guidance, not rigid rules:

| Situation | Default handling |
|---|---|
| Explanation, planning, or trivial task | Parent |
| Simple targeted lookup | Parent |
| Broad discovery or execution tracing | `code-explorer` |
| Clear low-risk localized edit | `quick-implementer` |
| Feature, refactor, or substantial fix | `implementer` |
| Explicit or risk-triggered review | `code-reviewer` |
| Explicitly authorized commit or push | `commit-pusher` |

The parent handles work directly when delegation would add overhead, when the change is small and clear, or when the work is tightly coupled enough that splitting it would increase risk. Delegation is reserved for clear benefit: reducing discovery cost, isolating a narrow implementation, handling substantial multi-file work, obtaining independent review for meaningful risk, or performing explicitly authorized Git actions.

Risk-based review is automatic only when justified. The parent must spawn a separate `code-reviewer` for explicit independent-review requests, security-sensitive changes, authn/authz, public API compatibility, persistence, migrations, concurrency, architectural changes, hard-to-validate behavior, or unusually risky diffs; a writing agent's self-check does not satisfy independent review. If the pinned custom agent cannot start, the parent reports the failure and uses an independent read-only fallback when available. Routine edits do not require automatic review.

Git publishing is opt-in. `commit-pusher` may stage, commit, or push only when the user explicitly authorizes those Git actions. A request to implement, fix, finish, complete, or deploy code is not commit or push authorization.

## Installed Resources

`install.sh` installs:

- `agents/*.toml` into `$CODEX_HOME/agents/`
- `rules/SUBAGENT_ROUTING.md` into `$CODEX_HOME/SUBAGENT_ROUTING.md`
- a managed import block in `$CODEX_HOME/AGENTS.md`
- a managed `[features.multi_agent_v2]` block in `$CODEX_HOME/config.toml` only when that feature table is absent
- `.subagents_configs-state.json` to track repository-owned resources for upgrades and uninstall

The always-loaded global instruction is deliberately small: it imports the routing-policy file. Longer design explanation stays in this README rather than being injected into every Codex session. Project-level `AGENTS.md` files can still add or override local repository guidance.

## Install

Prerequisite: Python 3.11 or newer. The installer uses the standard-library `tomllib` parser and exits before reading or modifying destination files when it is unavailable.

```sh
./install.sh
```

### Windows PowerShell

Current Codex releases enable multi-agent support by default, so the native Windows installer does not edit `config.toml` and does not require Python:

```powershell
git clone https://github.com/PipelineSteps/subagents_configs.git
Set-Location subagents_configs
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

Close and reopen Codex after installation so the new global instructions and custom agents are loaded. The default destination is `$env:CODEX_HOME` when set, otherwise `$env:USERPROFILE\.codex`.

Use a temporary or custom Codex home for testing:

```sh
CODEX_HOME="$(mktemp -d)" ./install.sh
```

Paths with spaces are supported:

```sh
CODEX_HOME="/tmp/codex home with spaces" ./install.sh
```

## Upgrades and Preservation

Existing files under `CODEX_HOME` are treated as user-owned. The installer:

- preserves unrelated content
- creates missing directories safely
- validates source agent TOML before modifying destinations
- validates existing `config.toml` with Python 3.11+ `tomllib`
- creates backups before modifying existing files
- uses managed blocks for `AGENTS.md` and installer-owned feature config
- uses atomic writes for all managed files and rolls back completed mutations if a later installation step fails
- avoids duplicate managed blocks, duplicate TOML tables, and repeated backups on no-op reinstalls
- preserves model, approval, sandbox, provider, and user preference settings

If an existing `config.toml` already defines `[features.multi_agent_v2]`, the installer leaves that table untouched. Without a full TOML writer, it does not try to merge missing keys into a user-owned table.

Older unmarked feature blocks are upgraded to a managed block only when they exactly match this repository's prior installed bytes. Otherwise they are treated as user-owned and preserved.

## Uninstall

```sh
./uninstall.sh
```

On Windows PowerShell:

```powershell
Set-Location subagents_configs
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall.ps1
```

Uninstall is conservative. It removes only resources recorded in `.subagents_configs-state.json` and still matching the installed bytes. It removes the managed `AGENTS.md` import block, removes the managed feature config only when this installer owns it, restores replaced files from backups where safe, and preserves modified or unrelated user content.

If installer state is missing or corrupt, uninstall refuses to guess.

## Model Assignments

Agent model identifiers are configured in `agents/*.toml` and are preserved by the installer:

- `code-explorer`: `gpt-5.6-luna`, medium reasoning
- `quick-implementer`: `gpt-5.6-luna`, low reasoning
- `implementer`: `gpt-5.6-luna`, high reasoning
- `code-reviewer`: `gpt-5.6-sol`, low reasoning
- `commit-pusher`: `gpt-5.6-luna`, low reasoning

This repository assumes those model identifiers are available in the target Codex environment. The routing policy changes when each agent is selected; it does not rename or replace models.

## Inspecting Delegated Activity

Each agent begins with a short delegation message naming the custom agent, model, and reasoning effort. Agents are instructed to return concise structured results: findings, file or symbol references, changes made, validation performed, unresolved concerns, and recommended next action.

The parent agent remains responsible for inspecting subagent output and the final diff. Subagent reports are inputs to the parent, not final authority.

## Validation

Run the repository validation script:

```sh
./test_install.sh
```

It validates agent TOML, shell syntax, clean install into temporary `CODEX_HOME`, repeated install idempotency, user-content preservation, legacy managed-block upgrade, uninstall, paths containing spaces, and malformed config failure behavior. It never uses the real Codex home.

## Known Limitations

- Python 3.11+ is required because the installer uses standard-library `tomllib` for TOML validation.
- The installer can safely append a missing feature table, but it will not edit a user-owned existing `[features.multi_agent_v2]` table to add or change keys.
- Uninstall relies on installer state. Without state, it preserves everything rather than guessing.
- Backups are retained for user recovery and are not automatically pruned.
- Native Windows installation requires PowerShell 5.1 or newer. The PowerShell installer validates source presence and preserves ownership, but full Windows execution is not exercised by the POSIX test suite.
