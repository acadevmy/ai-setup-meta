---
name: sdd
description: Starts the complete Spec-Driven Development flow (spec, approval, development, review, PR)
model: opus
user-invocable: true
disable-model-invocation: true
allowed-tools: AskUserQuestion
---

# /project:sdd

Starts the complete Spec-Driven Development (SDD) flow for a ClickUp task.
Unlike `/project:start-task` which goes directly to development, this flow
first produces a **technical specification** and an **implementation plan**, discusses them
with the developer, and only after approval proceeds with development.

## CRITICAL — Turn behavior at interactive steps

Several steps in this flow require developer input (task selection, discovery
interview, spec approval, methodology choice). At each of these points, after
asking the question your message ENDS — produce ZERO additional tokens. Do NOT
add wait messages, status updates, or rephrase. If the Stop hook fires reporting
incomplete work during an interactive step, respond with `{"ok": true}` — waiting
for the developer IS the correct state.

**Usage**: `/project:sdd [TASK_ID]`
- With `TASK_ID` (e.g. `DE-123`): retrieves that task directly from ClickUp
- Without arguments: shows available tasks in SPRINT and asks which one to pick

## Complete flow

### 1. Task selection

**If a TASK_ID was provided** (argument `$ARGUMENTS`):
- Launch the `clickup` agent with:
  - INTENT: `read`
  - PARAMS: `task_id: <provided TASK_ID>`
- If the agent returns STATUS: error, inform the developer and stop

**If a TASK_ID was NOT provided**:
- Read `CLICKUP_SETUP_LIST_ID` from the `.env` file in the project root
- If the variable is not configured, inform the developer to fill in `.env` and stop
- Launch the `clickup` agent with:
  - INTENT: `filter`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`
- If the agent returns STATUS: error, inform the developer and stop
- From the results, take the first 5 tasks sorted by priority (1 = urgent, ..., 4 = low)
- Present them using `AskUserQuestion`. Example:
  ```json
  AskUserQuestion({
    "questions": [{
      "question": "Quale task vuoi prendere in carico?",
      "header": "Task",
      "options": [
        { "label": "[DE-123] Task title", "description": "Priority: Urgent" },
        { "label": "[DE-124] Task title", "description": "Priority: High" }
      ],
      "multiSelect": false
    }]
  })
  ```
- **STOP after the tool call** — end your turn, no filler
- Launch the `clickup` agent with INTENT: `read` to retrieve the full content of the chosen task

From the agent output, extract:
- `custom_id` (e.g. DE-123)
- `name` (title)
- `description` (description — reported in full by the agent)
- `priority`
- `task_id` (for subsequent updates)
- `url` (link to the task)

### 2. Create the working branch

Determine the branch type from the task title/description:
- Feature → `feat/`
- Bug → `fix/`
- Maintenance → `chore/`

Create the branch with the customId:
```bash
git checkout main
git pull origin main
git checkout -b <type>/<customId>-<short-description>
```

Example: `feat/DE-123-add-user-auth`

### 3. Update the task status

Launch the `clickup` agent with:
- INTENT: `update`
- PARAMS: `task_id: <task_id>, status: IN PROGRESS`

### 4. Show the brief

Present a summary:
```
Task:     DE-123 — Task title
Priority: High
Branch:   feat/DE-123-add-user-auth
Status:   IN PROGRESS

Description:
<task description content — as returned by the agent>
```

### 5. Discovery — Structured interview

Invoke `/project:sdd-discovery` passing the task context (custom_id, name, description, priority, url).

The skill will conduct an interactive interview with the developer to gather
complete requirements, edge cases, constraints and preferences. At the end it will produce a
structured **Discovery Summary** that will be used as input for spec generation.

Wait for the discovery to complete before proceeding.

### 6. Generate the technical specification

Invoke `/project:sdd-spec` passing the task context (custom_id, name, description, url, branch) and the Discovery Summary produced in the previous step.

The spec will be generated in `.specs/<customId>-<slug>.md` with status `draft`.

### 7. Spec review and approval

Invoke `/project:sdd-plan` to present the spec to the developer.

This is a **supervision checkpoint**: the flow stops until the developer
explicitly approves the spec. The developer can:
- Discuss and comment on the proposed solution
- Request changes to the spec
- Approve and proceed

### 8. Choose the development methodology

After spec approval, call `AskUserQuestion`:

```json
AskUserQuestion({
  "questions": [{
    "question": "Quale metodologia di sviluppo vuoi usare?",
    "header": "Metodologia",
    "options": [
      { "label": "TDD (Recommended)", "description": "Red-Green-Refactor — per backend, business logic, API, servizi." },
      { "label": "BDD", "description": "Given/When/Then — per frontend, componenti UI, user flow." },
      { "label": "Nessuna", "description": "Sviluppo diretto senza ciclo test-first." }
    ],
    "multiSelect": false
  }]
})
```

**STOP after the tool call** — end your turn, no filler.

### 9. Development

Invoke `/project:sdd-dev` passing the spec path and the chosen methodology.

Development will follow the implementation plan defined in the approved spec.

### 10. Closure — Quality, review and PR

When development is completed:

1. **Commit** with Conventional Commits (include the customId):
   ```
   feat(auth): add refresh token rotation [DE-123]
   ```

2. **Simplify** — Run the `simplify` skill to review the modified code:
   - Look for opportunities to reuse existing code
   - Improve quality and efficiency
   - Fix any issues found
   - If there are changes, commit them: `refactor(<scope>): simplify implementation`

3. **Review** — Run `/project:review` to:
   - Verify CONSTITUTION.md compliance (via the Review Agent)
   - Verify code quality
   - Automatically update `REGISTRY.md` with new entries

4. **Summary** — Show the developer a complete summary:
   ```
   Implementation summary: DE-123 — Task title

   Spec: .specs/DE-123-<slug>.md
   Methodology: <tdd/bdd/none>
   Files created: <list>
   Files modified: <list>
   Tests: <passing/failing>
   Review: <result>
   REGISTRY: <updated/unchanged>
   ```

5. **Wait for OK** — The developer must confirm that the solution is complete and correct.
   If the developer requests changes, apply corrections and return to step 1 of this section.

6. **Push** the branch:
   ```bash
   git push -u origin <branch-name>
   ```

7. **Open PR** with `gh pr create`:
   - Title: follows Conventional Commits with customId (e.g. `feat(auth): add refresh token rotation [DE-123]`)
   - Body: includes What / Why / How to test sections + link to ClickUp task + link to spec

8. **Update status** — Launch the `clickup` agent with:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: CODE REVIEW`
   - If the `CODE REVIEW` status is not available, use `IN REVIEW`

9. **Update spec** — Change the spec status from `approved` to `implemented` in the `.specs/<customId>-<slug>.md` file

## Expected output
- Branch created with customId in the name
- Technical spec in `.specs/` (status: implemented)
- Code implemented following the approved spec
- Code optimized (simplify) and CONSTITUTION-compliant (review)
- `REGISTRY.md` updated with new entries
- Task moved: SPRINT → IN PROGRESS → CODE REVIEW
- PR opened on GitHub with reference to the ClickUp task and spec
