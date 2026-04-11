---
name: verify
description: Verifies that the implementation matches the approved spec (completeness, correctness, coherence)
model: sonnet
user-invocable: true
disable-model-invocation: false
allowed-tools: AskUserQuestion
---

# /project:verify

Verifies that the current implementation matches the approved technical spec.
Unlike `/project:review` which checks **code quality** (CONSTITUTION compliance),
this skill checks **spec conformance**: did we build what we said we would build?

**Usage**: `/project:verify [SPEC_PATH]`
- With `SPEC_PATH`: uses the specified spec file
- Without arguments: auto-detects the spec from the current branch name (e.g. `feat/DE-123-slug` → `.specs/DE-123-*.md`)

## Procedure

### 1. Load the spec

**If `$ARGUMENTS` contains a path**:
- Read the file at the given path
- If the file does not exist, inform the developer and stop

**If `$ARGUMENTS` is empty**:
- Extract the customId from the current branch name (e.g. `feat/DE-123-desc` → `DE-123`)
- Search for a matching spec: `.specs/<customId>-*.md`
- If no spec is found, inform the developer and stop
- If multiple specs match, use the most recent one (by `Created` date in frontmatter)

Verify that the spec status is `approved` or `implemented`. If `draft`, warn the developer
that the spec has not been approved yet and ask whether to proceed anyway.

### 2. Load the diff

Run `git diff main...HEAD --name-only` to get the list of changed files.
Run `git diff main...HEAD` to get the full diff content.

If there are no changes against main, inform the developer and stop.

### 3. Check Completeness

For each `REQ-N` in the `## Requirements` section:

1. Extract the requirement description text
2. Search the diff for evidence of implementation:
   - Look for files, functions, classes, or logic that correspond to the requirement
   - Check that test files cover the requirement (search for test descriptions matching the requirement intent)
3. Classify as:
   - **covered**: clear evidence found in both implementation and tests
   - **partial**: implementation found but no test coverage, or test found but implementation unclear
   - **not-found**: no evidence in the diff

For each entry in the `## Test strategy` section:

1. Extract the test description
2. Search test files in the diff for a matching test case (by description or intent)
3. Classify as: **found** or **not-found**

### 4. Check Correctness

Compare the `## Impact` section against the actual diff:

1. **Files to create**: for each listed file, check if it appears as a new file in the diff
2. **Files to modify**: for each listed file, check if it appears as a modified file in the diff
3. **Dependencies**: for each listed dependency, check if it was added to `package.json`, `pubspec.yaml`, or the relevant dependency file

Flag:
- **Missing**: files listed in Impact but not present in the diff
- **Unexpected**: files in the diff that are not listed in Impact and are not test files, config files, or obvious support files (use judgment — a new type definition file supporting a listed service is expected; a completely unrelated module is not)

### 5. Check Coherence

Read the `## Technical decisions` section. For each stated decision:

1. Search the diff for evidence that the decision was followed
   - Example: "Use Zod for validation" → look for Zod imports in new files
   - Example: "Repository pattern" → look for repository class/file
   - Example: "ShadCN/UI components" → look for ShadCN imports
2. Classify as: **followed** or **not-found**

If a decision was not followed, check whether an alternative was used and note it
(e.g. spec says "Zod" but code uses "class-validator" — flag as divergence, not just missing).

### 6. Produce the result

Format the output as:

```
---VERIFY-RESULT---
STATUS: pass | fail | pass-with-warnings

COMPLETENESS:
  Requirements:
  - REQ-1: <status> — <brief evidence or what's missing>
  - REQ-2: <status> — <brief evidence or what's missing>
  Tests:
  - Test 1: <found|not-found> — <test file:line or what's missing>
  - Test 2: <found|not-found> — <test file:line or what's missing>

CORRECTNESS:
  Expected files touched: <N>/<total>
  Missing: <list of files listed in Impact but not in diff, or "none">
  Unexpected: <list of files in diff but not in Impact, or "none">
  Dependencies: <all added | list of missing>

COHERENCE:
  - "<decision>": <followed|not-found|diverged — actual: ...>

SUMMARY: <one-line overall assessment>
---END---
```

**STATUS classification**:
- **pass**: all REQ-N are `covered`, all tests `found`, no missing files, all decisions `followed`
- **pass-with-warnings**: all REQ-N are at least `partial`, minor unexpected files, or minor divergences with reasonable justification
- **fail**: any REQ-N is `not-found`, or multiple tests are `not-found`, or critical decisions were `diverged`

### 7. Report to the developer

**If STATUS = fail**:
- Show the full VERIFY-RESULT
- List specifically what is missing or divergent
- Suggest concrete next steps (e.g. "implement REQ-3" or "add test for expired token scenario")
- Do NOT proceed — the implementation needs work

**If STATUS = pass-with-warnings**:
- Show the full VERIFY-RESULT
- Highlight warnings and ask if they are intentional scope reductions
- Proceed if the developer confirms

**If STATUS = pass**:
- Show the full VERIFY-RESULT
- Confirm that the implementation matches the spec

## Expected output
- Structured VERIFY-RESULT report comparing spec vs implementation
- Clear indication of what matches and what is missing
- Actionable suggestions for any gaps found
