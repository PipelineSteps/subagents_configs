# Subagent Routing

For each new user request, the active parent Codex session silently classifies the work before acting. The parent remains the coordinator: it understands the complete request, captures constraints and acceptance criteria, decides whether delegation is useful, sequences specialists, resolves conflicts, inspects the final result, verifies validation, and reports back to the user.

Do not create or rely on a permanent orchestrator subagent. The parent handles work directly unless a specialist offers a clear benefit.

## Classification

Consider intent, scope, coupling, uncertainty, risk, required permissions, and validation needs.

- Intent: answer, plan, inspect, trace behavior, diagnose, implement, fix, refactor, test, review, stage, commit, push, or mixed workflow.
- Scope and coupling: trivial vs substantial, known vs unknown code, localized vs cross-cutting, tightly coupled vs safely separable.
- Uncertainty: targeted lookup, broad discovery, execution tracing, architectural investigation, or unresolved assumptions.
- Risk: user-visible behavior, public API compatibility, authentication or authorization, secrets, security boundaries, persistence, migrations, destructive actions, concurrency, dependencies, deployment, rollback difficulty, or weak validation.
- Permissions: read-only, workspace write, network, command execution, Git staging, Git commit, Git push, or destructive operations.
- Validation: source inspection, targeted tests, linting, formatting, type checking, build, integration tests, manual reproduction, broad suites, or independent review.

Optimize in this order unless a project `AGENTS.md` says otherwise: correctness and safety, minimum necessary permissions, avoiding unnecessary delegation, monetary cost, total tokens, then latency.

## Default Routing

Prefer this order:

1. Parent handles the task directly.
2. Parent delegates one clearly bounded specialist task.
3. Parent coordinates a multi-stage workflow only when needed.

Use the parent directly for questions, explanations, planning, trivial repository operations, small edits where delegation adds overhead, tightly coupled work best handled in one context, final integration, and final reporting. A matching subagent is not enough reason to delegate.

Use `code-explorer` when relevant code locations are unclear, execution behavior must be traced, repository-wide discovery is needed, architecture or impact must be mapped, or read-only investigation would consume substantial parent context. Do not use it for a simple symbol lookup the parent can perform quickly.

Use `quick-implementer` when the change is well defined, behavior and affected area are understood, risk is low, implementation is localized, validation is narrow and clear, and escalation is possible if scope expands. Do not choose it only because the expected file count is small.

Use `implementer` for meaningful feature work, nontrivial bug diagnosis or fixes, multiple related components, test design, refactoring, behavioral integration, or work beyond `quick-implementer` scope.

Spawn a separate `code-reviewer` subagent when the user explicitly asks for independent review, or when the diff affects security-sensitive behavior, authentication or authorization, public APIs or compatibility, concurrency or transactions, migrations or persistent data, architecture, difficult-to-validate behavior, or a substantial/unusually risky change. The writing agent's self-check is not an independent review. If the custom agent cannot start, report that failure and use an independent read-only fallback agent when available. The parent may perform ordinary requested code review directly when independence is not requested and no risk trigger applies. Do not run `code-reviewer` automatically for every routine edit.

Use `commit-pusher` only when the user explicitly requests staging, commit, push, or a combination of those Git actions. Implementation must be complete, intended files identified, validation adequate, the final diff inspected, and unrelated or sensitive files excluded. Never infer commit or push authorization from requests to implement, fix, finish, complete, or deploy code.

## Delegation Rules

When delegation is useful, keep it bounded and independently verifiable.

- Use one specialist unless independent workstreams clearly justify more.
- Prefer parallel read-only investigation over parallel writing.
- Do not allow multiple agents to edit overlapping files concurrently.
- Do not review a diff while another agent is still changing it.
- Do not run `commit-pusher` concurrently with writing or review.
- Assign explicit, non-overlapping file or module ownership for parallel implementation.
- Tell subagents the workspace is shared and unrelated changes must be preserved.
- Ask for concise structured results: findings, file/symbol references, changes made, validation performed, unresolved concerns, and recommended next action.
- Use `fork_turns="none"` unless parent conversation context is genuinely required.

The parent must still inspect and validate the final outcome, even when no independent review is used.
