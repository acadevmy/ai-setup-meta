---
name: review
description: Reviews the current branch's diff against the project rules through the code-reviewer agent, then records the components it found in REGISTRY.md. Use when a branch is ready and its code quality and rule compliance have to be checked before a merge request.
effort: max
user-invocable: true
disable-model-invocation: false
---

# Review

Review the code this branch changed, against the rules this project declares.
`verify` checks that the implementation matches the spec; this skill checks the
code itself.

**Input**: optionally `PACKAGE` and `SIZE`. The `sdd` closure builds the
package once and passes it to both `verify` and this skill; invoked on its own,
this skill builds it.

## Before you start

- **`reference/registry-updates.md`** — how the findings land in `REGISTRY.md`,
  why nothing here commits, and the final report's shape.

## Procedure

### 1. Resolve the package

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

Use its `MERGE_BASE` (the fork point), `TASK_ID` and `SPEC`. Never assume
`main`: on a project targeting `next`, that reviews the whole delta between the
two long-lived branches.

With a `PACKAGE` given, use it and its `SIZE`. Without one, build it — and stage
first (`git add -A`), because an untracked file has no diff; the script itself
never touches the index:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-package.sh" --base <MERGE_BASE> --json
```

`EMPTY=true` means there is nothing to review: say so and stop, with no agent
launched. **Do not read the package here** — the agents do.

### 2. Launch the code-reviewer agent

Launch the `code-reviewer` agent with `PACKAGE`, `RULES_DIR` (`./.claude/rules/`),
`REGISTRY_PATH` (`./REGISTRY.md`) and `TASK_ID` if there is one.

The model follows the size: when `SIZE` is `large`, launch it with `model: fable`;
otherwise pass no model and the definition's default applies.

### 3. Validate the violations

With no violations, the validator is not launched. When there are some, a
second look decides which ones hold before any of them blocks the merge:

Launch the `finding-validator` agent with `PACKAGE`, `RULES_DIR` and the
`VIOLATIONS` entries verbatim. It returns `CONFIRMED` and `DISCARDED`.

If it returns no `---VALIDATION-RESULT---` block, every violation stands as
confirmed: an error is not a pass.

### 4. Read the result

The status is decided on `CONFIRMED`, not on the reviewer's own `STATUS`:

- **fail** — at least one confirmed violation. Show each with its file, line,
  rule and proof, the discarded ones with their reason, and the warnings as
  suggestions. Stop: the code has to be fixed first.
- **pass-with-warnings** — none confirmed, warnings present: show them and carry on.
- **pass** — none confirmed, no warnings: carry on.

### 5. Write the findings back

Follow `reference/registry-updates.md`: the `REGISTRY.md` entries, then the
report. Commit neither — inside the SDD flow, closure commits once and carries
them.

## Expected output

- a compliance report against the project rules;
- `REGISTRY.md` updated in the working tree, uncommitted, when there were
  entries to add.
