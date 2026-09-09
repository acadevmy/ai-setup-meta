---
name: review
description: Reviews the current branch's diff against the project rules through the review agent, then records what it found in REGISTRY.md and in the spec. Use when a branch is ready and its code quality and rule compliance have to be checked before a merge request.
effort: max
user-invocable: true
disable-model-invocation: false
---

# Review

Review the code this branch changed, against the rules this project declares.
`verify` checks that the implementation matches the spec; this skill checks the
code itself.

## Before you start

- **`reference/registry-and-spec.md`** — how the findings land in `REGISTRY.md`
  and in the spec's `## Review phase` section, and the final report's shape.

## Procedure

### 1. Resolve the base branch

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

Use its `MERGE_BASE` (the fork point), `TASK_ID` and `SPEC`. Never assume
`main`: on a project targeting `next`, that reviews the whole delta between the
two long-lived branches.

### 2. Launch the review agent

Launch the `review` agent with:

- `BASE_BRANCH`: the `MERGE_BASE` from step 1
- `RULES_DIR`: `./.claude/rules/`
- `REGISTRY_PATH`: `./REGISTRY.md`
- `TASK_ID`: the `TASK_ID` from step 1, if there is one

### 3. Read the result

Parse the `---REVIEW-RESULT---` block the agent returns.

- **fail** — show every violation with its file, line and the rule it breaks,
  and the warnings as suggestions. Stop: the code has to be fixed first.
- **pass-with-warnings** — show the warnings as improvements and carry on.
- **pass** — confirm compliance and carry on.

### 4. Write the findings back

Follow `reference/registry-and-spec.md`: the `REGISTRY.md` entries first, then
the spec's `## Review phase` section, then the report.

## Expected output

- a compliance report against the project rules;
- `REGISTRY.md` updated, with a `docs(registry): update REGISTRY.md` commit when
  there were entries to add;
- the spec's `## Review phase` section filled in, when a spec exists.
