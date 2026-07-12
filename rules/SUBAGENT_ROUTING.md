# Subagent Routing

Default to completing work in the parent agent. Delegate only when there is a concrete reason to expect lower monetary cost, lower total token usage, materially less parent-context growth, or useful independent parallelism. Count the parent prompt, subagent prompt, duplicated discovery, tool output, and handoff summary; optimize for estimated monetary cost first and total tokens second.

Do not delegate trivial conversation, known-target work limited to one or two files, straightforward commands, or tasks likely to finish within a few focused tool calls. A slow command alone is not a reason to delegate. Run ordinary Python, Gradle, test, build, lint, migration, and generator commands directly with bounded output. Delegate runner work only for substantial iterative diagnosis, output analysis, or genuinely independent parallel execution.

When delegation is justified:

- Use `fork_turns="none"` unless parent conversation context is genuinely required.
- Prefer one subagent per task. Add more only for non-overlapping work that materially saves time without duplicating discovery.
- Reuse an existing subagent for closely related follow-up work when that avoids repeated discovery.
- Give task-local prompts and request decision-ready reports of at most 300 words: findings, evidence locations, risks, and next action. Exclude narration, raw dumps, and repeated context.
- Trust cited subagent findings; do not repeat its discovery unless verification is necessary.

Select custom agents by their exact `name` from `~/.codex/agents`:

- Broad repository discovery, contract or data-flow tracing -> `code-explorer`
- Mechanical one- or two-file change when delegation still saves cost -> `quick-implementer`
- Multi-file behavior change, debugging, or substantial tests -> `implementer`
- Independent review only for high-risk, security-sensitive, architectural, public-API, migration, concurrency, or difficult-to-validate changes -> `code-reviewer`
- Commit and push, only when the user explicitly requests both -> `commit-pusher`

Do not use a fixed command-count threshold for exploration. Use `code-explorer` only when discovery is expected to cross several files, require meaningful tracing, or add substantial raw evidence to the parent context. Do not use it to reread known files.

Use the cheapest role and reasoning effort that can reliably complete the work. Do not substitute built-in generic agents when the matching custom agent is available. Avoid duplicate investigation and parallel write-heavy delegation; parallel writes must have non-overlapping ownership.
