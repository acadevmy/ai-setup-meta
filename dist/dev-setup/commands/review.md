---
description: "Performs code review of the current branch verifying CONSTITUTION compliance and updating REGISTRY"
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

### 4. Final report

Show a summary:
```
Review: <STATUS>
Violations: <count>
Warnings: <count>
REGISTRY updated: <yes/no>

<SUMMARY from agent>
```

## Expected output
- CONSTITUTION compliance report
- `REGISTRY.md` updated with new entries (if any)
- Commit `docs(registry): update REGISTRY.md` (if registry changes)
