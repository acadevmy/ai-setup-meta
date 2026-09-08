---
name: review
description: Performs code review of the current branch verifying CONSTITUTION compliance and updating REGISTRY
effort: max
user-invocable: true
disable-model-invocation: false
---

# /project:review

Perform a code review of the modified code in the current branch via the Review Agent.

## Procedure

### 1. Launch the Review Agent

Launch the `review` agent with:
- BASE_BRANCH: `main`
- CONSTITUTION_PATH: `./CONSTITUTION.md`
- REGISTRY_PATH: `./REGISTRY.md`
- TASK_ID: extracted from the current branch name (e.g. `feat/DE-123-desc` → `DE-123`), if present

### 2. Analyze the result

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

### 3. Apply REGISTRY updates

If the agent returned non-empty REGISTRY_UPDATES:

1. Read the current `REGISTRY.md`
2. For each entry with ACTION: `add`:
   - Add the ENTRY block in the indicated SECTION
   - Remove any placeholder `_No ... registered._` from the section
3. For each entry with ACTION: `update`:
   - Find the existing entry in the section and update the modified fields
4. Commit the update: `docs(registry): update REGISTRY.md`

### 4. Track the outcome in the spec

Locate the spec for the current task:
- Extract the customId from the current branch name (e.g. `feat/DE-123-desc` → `DE-123`)
- Find `.specs/<customId>-*.md`
- If no spec exists, skip this step (the review was likely invoked outside the SDD flow)

Update the `## Review phase` section of the spec with:
- `State`: `completed`
- `Date`: today's date, as `YYYY-MM-DD`
- `Outcome`: the STATUS the Review Agent returned (`pass`, `pass-with-warnings`, `fail`)
- `Violations`: the number of CONSTITUTION violations found
- `Warnings`: a short list of the warnings with their rationale (e.g. `W-1: missing test for X`), or `none`
- `REGISTRY updates`: the number of entries applied + a short add/update summary per section, or `none`

Overwrite the existing section and leave the rest of the spec untouched. If REGISTRY commits have already been made (`docs(registry): update REGISTRY.md`), put the spec update in an extra commit `docs(spec): track review outcome`, or fold it into the same REGISTRY commit while the stage is still open.

### 5. Final report

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
- CONSTITUTION compliance report
- `REGISTRY.md` updated with new entries (if any)
- Commit `docs(registry): update REGISTRY.md` (if registry changes)
- Spec file updated with the `## Review phase` section filled in (when the spec exists)
