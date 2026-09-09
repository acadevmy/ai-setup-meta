---
name: verify
description: Checks the branch's diff against the approved spec — every requirement covered, every planned test present, the Impact list respected, the technical decisions followed. Use when development is finished and spec conformance has to be established before review.
effort: high
user-invocable: false
disable-model-invocation: false
allowed-tools: AskUserQuestion
---

# SDD verify

Answer one question: did we build what we said we would build? `review` checks
**code quality** against the project rules; this skill checks **spec
conformance**, and the two are not substitutes.

**Input**: optionally a spec path. Without one, the spec is resolved from the
current branch (`feat/DE-123-slug` → `.specs/DE-123-*.md`).

## Before you start

- **`reference/checks.md`** — the three checks (completeness, correctness,
  coherence), the result block, and how the status is classified.

## Procedure

### 1. Collect the prerequisites

One call resolves the spec, the plan, the base branch and the changed files:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

It returns `SPEC`, `SPEC_STATUS`, `PLAN`, `CHANGED_FILES`, `BASE_BRANCH`,
`MERGE_BASE`, `TASK_ID`, `AVAILABLE_DOCS`. With a path in `$ARGUMENTS`, use that
file instead of the `SPEC` key (`--task <customId>` looks a different task up).

If `SPEC` is empty, say so and stop. If `SPEC_STATUS` is `draft`, warn that the
spec was never approved and ask whether to proceed anyway.

### 2. Load the diff

`MERGE_BASE` is the commit the branch forked from, so the diff holds this
branch's own work and nothing else:

```bash
git diff <MERGE_BASE> --stat
git diff <MERGE_BASE>
```

Never diff against a hard-coded `main`: on a project whose work targets `next`
or `develop`, that reports the whole delta between the long-lived branches as
part of the branch, and every file in it comes back as "Unexpected".

If `CHANGED_FILES` is empty, say so and stop.

### 3. Run the three checks

Follow `reference/checks.md` and produce the `---VERIFY-RESULT---` block.

### 4. Report

- **fail** — show the block, list exactly what is missing or divergent, suggest
  the concrete next step ("implement REQ-3", "add a test for the expired token
  scenario"). Do not proceed: the implementation needs work.
- **pass-with-warnings** — show the block, highlight the warnings, and ask
  whether they are intentional scope reductions. Proceed on a confirmation.
- **pass** — show the block and confirm the implementation matches the spec.

## Expected output

- a `---VERIFY-RESULT---` report comparing spec against implementation;
- an explicit list of what matches and what does not;
- an actionable suggestion for every gap.
