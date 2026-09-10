---
name: verify
description: Checks the branch's diff against the approved spec — every requirement covered, every planned test present, the Impact list respected, the technical decisions followed. Use when development is finished and spec conformance has to be established before review.
effort: medium
user-invocable: false
disable-model-invocation: false
---

# SDD verify

Answer one question: did we build what we said we would build? `review` checks
**code quality** against the project rules; this skill checks **spec
conformance**, and the two are not substitutes.

**Input**: optionally a spec path. Without one, the spec is resolved from the
current branch (`feat/DE-123-slug` → `.specs/DE-123-*.md`).

The comparison itself runs in the `spec-verifier` agent, the same shape `review`
uses: the diff is unbounded and belongs in an isolated context, while this skill
handles the resolution before it and the reporting after it.

## Before you start

- **`reference/checks.md`** — the three checks (completeness, correctness,
  coherence), the result block, and how the status is classified. The agent
  works from this file; read it to interpret what comes back.

## Procedure

### 1. Collect the prerequisites

One call resolves the spec, the plan, the base branch and the changed files:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

It returns `SPEC`, `SPEC_STATUS`, `PLAN`, `CHANGED_FILES`, `BASE_BRANCH`,
`MERGE_BASE`, `TASK_ID`, `AVAILABLE_DOCS`. With a path in `$ARGUMENTS`, use that
file instead of the `SPEC` key (`--task <customId>` looks a different task up).

If `SPEC` is empty, say so and stop. If `CHANGED_FILES` is empty, say so and
stop. If `SPEC_STATUS` is `draft`, warn that the spec was never approved and ask
whether to proceed anyway.

### 2. Launch the verification agent

Launch the `spec-verifier` agent with:

- `SPEC`: the spec path from step 1
- `MERGE_BASE`: the `MERGE_BASE` from step 1 — the fork point, never a
  hard-coded `main`
- `CHECKS_PATH`: `${CLAUDE_PLUGIN_ROOT}/skills/verify/reference/checks.md`
- `TASK_ID`: the `TASK_ID` from step 1, if there is one

**Do not run `git diff` here.** The agent reads it; pulling it into this context
too pays for it twice and is what this split exists to avoid.

### 3. Read the result

Parse the `---VERIFY-RESULT---` block the agent returns.

- **fail** — show the block, list exactly what is missing or divergent, suggest
  the concrete next step ("implement REQ-3", "add a test for the expired token
  scenario"). Do not proceed: the implementation needs work.
- **pass-with-warnings** — show the block, highlight the warnings, and ask
  whether they are intentional scope reductions. Proceed on a confirmation.
- **pass** — show the block and confirm the implementation matches the spec.
- **error** — the agent could not run the check (a spec or a ref it could not
  resolve). Report what it says and stop: an error is not a pass.

## Expected output

- a `---VERIFY-RESULT---` report comparing spec against implementation;
- an explicit list of what matches and what does not;
- an actionable suggestion for every gap.
