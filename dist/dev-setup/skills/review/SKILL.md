---
name: review
description: Performs code review of the current branch against the project rules and updates REGISTRY
effort: max
user-invocable: true
disable-model-invocation: false
---

# /project:review

Perform a code review of the modified code in the current branch via the Review Agent.

## Procedure

### 1. Resolve the base branch

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

Use its `MERGE_BASE` (the fork point), `TASK_ID` and `SPEC`. Never assume `main`:
on a project targeting `next` that reviews the whole delta between the two
long-lived branches.

### 2. Launch the Review Agent

Launch the `review` agent with:
- BASE_BRANCH: the `MERGE_BASE` from the previous step
- RULES_DIR: `./.claude/rules/`
- REGISTRY_PATH: `./REGISTRY.md`
- TASK_ID: the `TASK_ID` from the previous step, if present

### 3. Analyze the result

Parse the `---REVIEW-RESULT---` output returned by the agent.

**If STATUS = fail**:
- Show all VIOLATIONS with file, line and violated rule
- Show WARNINGS as suggestions
- Inform the developer that the review did not pass
- Stop — the code must be fixed before proceeding

**If STATUS = pass-with-warnings**:
- Show WARNINGS as improvement suggestions
- Proceed to the next step

**If STATUS = pass**:
- Confirm that the code is compliant
- Proceed to the next step

### 4. Apply REGISTRY updates

If the agent returned non-empty REGISTRY_UPDATES:

1. Read the current `REGISTRY.md`
2. For each entry with ACTION: `add`:
   - Add the ENTRY block in the indicated SECTION
   - Remove any placeholder `_No ... registered._` from the section
3. For each entry with ACTION: `update`:
   - Find the existing entry in the section and update the modified fields
4. Commit the update: `docs(registry): update REGISTRY.md`

### 5. Track the outcome in the spec

Take the spec from `SPEC` (step 1). If it is empty, skip this step — the review
was invoked outside the SDD flow.

Update the spec's `## Review phase` section with:
- `State`: `completed`
- `Date`: today's date, as `YYYY-MM-DD`
- `Outcome`: the STATUS the Review Agent returned (`pass`, `pass-with-warnings`, `fail`)
- `Violations`: the number of rule violations found
- `Warnings`: a short list of the warnings with their rationale (e.g. `W-1: missing test for X`), or `none`
- `REGISTRY updates`: the number of entries applied + a short add/update summary per section, or `none`

Overwrite that section only, leaving the rest of the spec untouched. If the
REGISTRY commit is already made, add `docs(spec): track review outcome`;
otherwise fold both into it.

### 6. Final report

Show a summary:
```
Review: <STATUS>
Violations: <count>
Warnings: <count>
REGISTRY updated: <yes/no>
Spec updated: <yes/no>

<SUMMARY from agent>
```

## Expected output
- compliance report against the project rules
- `REGISTRY.md` updated with new entries (if any)
- Commit `docs(registry): update REGISTRY.md` (if registry changes)
- Spec file updated with the `## Review phase` section filled in (when the spec exists)
