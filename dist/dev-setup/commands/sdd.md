---
description: "Starts the complete Spec-Driven Development flow (spec, approval, development, review, PR)"
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

**Ask the developer which base branch to use**:

1. Run `git branch -r --sort=-committerdate | head -10` to detect available remote branches
2. Strip the `origin/` prefix and filter out `HEAD`
3. Build the `AskUserQuestion` options dynamically from the detected branches (max 4).
   For each branch, use the branch name as `label` and add context as `description`
   (e.g. last commit date or "branch principale" for main/master)
4. The developer can always select "Other" to type a custom branch name

Create the branch from the chosen base:
```bash
git checkout <base-branch>
git pull origin <base-branch>
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

3. **Verify** — Run `/project:verify` to check spec conformance:
   - Verify that all requirements (REQ-N) from the spec are implemented
   - Verify that all planned tests exist
   - Verify that the files in Impact were actually touched
   - Verify that technical decisions were followed
   - If STATUS = fail: show what is missing and return to development (step 9)
   - If STATUS = pass-with-warnings: show warnings and ask the developer to confirm
   - If STATUS = pass: proceed to review

4. **Review** — Run `/project:review` to:
   - Verify CONSTITUTION.md compliance (via the Review Agent)
   - Verify code quality
   - Automatically update `REGISTRY.md` with new entries

5. **Summary** — Show the developer a complete summary:
   ```
   Implementation summary: DE-123 — Task title

   Spec: .specs/DE-123-<slug>.md
   Methodology: <tdd/bdd/none>
   Files created: <list>
   Files modified: <list>
   Tests: <passing/failing>
   Verify: <pass/pass-with-warnings/fail>
   Review: <result>
   REGISTRY: <updated/unchanged>
   ```

6. **Wait for OK** — The developer must confirm that the solution is complete and correct.
   If the developer requests changes, apply corrections and return to step 1 of this section.

7. **Push** the branch:
   ```bash
   git push -u origin <branch-name>
   ```

8. **Open the merge/pull request** by invoking the active VCS-ops skill — `github-ops` if the repo's `origin` points at GitHub, `gitlab-ops` if it points at GitLab. Each skill self-identifies and bails if invoked on the wrong provider, so the correct one proceeds automatically.
   - Title: follows Conventional Commits with customId (e.g. `feat(auth): add refresh token rotation [DE-123]`)
   - Body: includes What / Why / How to test sections + link to ClickUp task + link to spec. On GitLab, the body follows `.gitlab/merge_request_templates/Default.md` when present (see `gitlab-ops`).

9. **Update status** — Launch the `clickup` agent with:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: CODE REVIEW`
   - If the `CODE REVIEW` status is not available, use `IN REVIEW`

10. **Update spec** — Change the spec status from `approved` to `implemented` in the `.specs/<customId>-<slug>.md` file

## Expected output
- Branch created with customId in the name
- Technical spec in `.specs/` (status: implemented)
- Code implemented following the approved spec
- Code verified against spec (verify), optimized (simplify) and CONSTITUTION-compliant (review)
- `REGISTRY.md` updated with new entries
- Task moved: SPRINT → IN PROGRESS → CODE REVIEW
- MR/PR opened (GitLab merge request or GitHub pull request, depending on the repo's provider) with reference to the ClickUp task and spec
